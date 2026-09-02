//
//  LocalWhisperTranscriptionService.swift
//  Ramble
//

import AVFoundation
import Combine
import CoreML
import Foundation
import SpeakerKit
import WhisperKit

/// On-device Whisper large-v3-turbo via WhisperKit (CoreML, runs on the Neural Engine).
///
/// The model is ~626 MB and is not shipped in the app bundle, so selecting this
/// provider starts a download. The resolved model folder is remembered in
/// `UserDefaults`, with a disk scan as the fallback, so a lost key never costs
/// the user a second 626 MB transfer.
@MainActor
final class LocalWhisperTranscriptionService: ObservableObject {
    static let shared = LocalWhisperTranscriptionService()

    /// Argmax's recommended variant for iPhone: large-v3 turbo, quantized to 626 MB.
    /// https://huggingface.co/argmaxinc/whisperkit-coreml
    static let modelVariant = "openai_whisper-large-v3-v20240930_626MB"
    static let modelDownloadSizeLabel = "626 MB"

    enum State: Equatable {
        case notDownloaded
        case downloading(Double)
        case ready
        case failed(String)
    }

    @Published private(set) var state: State

    /// Live status while a transcription runs, e.g. "Loading model…" or
    /// "Transcribing… 40%". Nil when idle. Only one job runs at a time, so a
    /// single value is enough.
    @Published private(set) var progressLabel: String?

    private var pipe: WhisperKit?
    private var loadTask: Task<WhisperKit, Error>?
    private var speakerKit: SpeakerKit?
    private var downloadTask: Task<Void, Error>?
    private var lastReportedPercent = 0

    /// Below this, Whisper was unsure enough about a stretch that another language
    /// is worth considering. Typical values for a clean decode sit above -0.5.
    private static let strugglingScore: Float = -0.7
    /// How much better a challenger must score before it replaces a stretch.
    private static let winningMargin: Float = 0.15

    private static let modelFolderKey = "localWhisperModelFolder"

    /// Application Support, not Caches — iOS may evict Caches under disk pressure,
    /// and a 626 MB re-download is not something to lose silently.
    private static var downloadBase: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WhisperModels", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    /// Where the weights are, or nil if they aren't on disk.
    ///
    /// The remembered path is only a fast path. A force-quit right after a download
    /// can lose the `UserDefaults` write while the 626 MB of weights sit there
    /// perfectly intact, and re-downloading them because of a missing key is the
    /// worst failure this service has, so a miss falls back to looking on disk.
    private static var savedModelFolder: URL? {
        if let path = UserDefaults.standard.string(forKey: modelFolderKey),
           FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        guard let found = locateModelFolderOnDisk() else { return nil }
        UserDefaults.standard.set(found.path, forKey: modelFolderKey)
        return found
    }

    /// Look for a `<variant>` directory under the download base that actually holds
    /// compiled CoreML models. A half-finished download leaves the directory without
    /// them, and that must not read as installed.
    private static func locateModelFolderOnDisk() -> URL? {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: downloadBase,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return nil }

        for case let url as URL in enumerator where url.lastPathComponent == modelVariant {
            let contents = (try? fileManager.contentsOfDirectory(atPath: url.path)) ?? []
            if contents.contains(where: { $0.hasSuffix(".mlmodelc") }) {
                return url
            }
        }
        return nil
    }

    private init() {
        state = Self.savedModelFolder == nil ? .notDownloaded : .ready
    }

    var isModelInstalled: Bool { Self.savedModelFolder != nil }

    var isDownloading: Bool {
        if case .downloading = state { return true }
        return false
    }

    /// Why recording is currently blocked, or nil if it isn't. Recording while the
    /// selected model is still downloading would just queue a job that fails, so the
    /// record button stays disabled until the weights are on disk.
    var recordingBlockedReason: String? {
        guard SettingsService.shared.load().transcriptionProvider == .localWhisper else { return nil }
        // Disk wins over `state`: once the weights are there, recording is fine
        // whatever the in-memory progress says.
        if isModelInstalled { return nil }
        switch state {
        case .ready:
            return nil
        case .downloading(let fraction):
            return "Downloading Whisper model… \(Int(fraction * 100))%"
        case .notDownloaded:
            return "Whisper model not downloaded — start it in Settings"
        case .failed:
            return "Whisper model download failed — retry in Settings"
        }
    }

    /// Pick a download back up after a relaunch. The transfer itself runs on a
    /// background URLSession, so leaving the app doesn't cancel it, but the
    /// in-process progress publisher dies with the process.
    /// Start (or keep) the model resident while the app is in use. Safe to call
    /// repeatedly: it no-ops once the pipeline is loaded.
    func keepModelWarm() {
        guard SettingsService.shared.load().transcriptionProvider == .localWhisper else { return }
        preload()
    }

    func resumeDownloadIfNeeded() {
        guard SettingsService.shared.load().transcriptionProvider == .localWhisper else { return }

        guard !isModelInstalled else {
            preload()
            return
        }
        guard downloadTask == nil else { return }
        Task { try? await downloadModel() }
    }

    /// Load the pipeline ahead of the first recording. CoreML specialization of the
    /// weights takes most of a cold transcription's wall clock, and doing it at
    /// launch means the first transcript isn't the one that pays for it.
    ///
    /// The loaded pipeline is then held for the life of the process, so a second
    /// recording in the same session pays nothing. Internal, because callers should
    /// go through `keepModelWarm()`.
    private func preload() {
        guard pipe == nil, let folder = Self.savedModelFolder else { return }
        Task { _ = try? await loadPipe(modelFolder: folder) }
    }

    // MARK: - Download

    /// Download the model. Reentrant: a second call while a download is in flight
    /// awaits the first one instead of starting a parallel 626 MB transfer.
    func downloadModel() async throws {
        if isModelInstalled {
            state = .ready
            return
        }

        if let existing = downloadTask {
            try await existing.value
            return
        }

        let task = Task { @MainActor in
            state = .downloading(0)
            do {
                let folder = try await WhisperKit.download(
                    variant: Self.modelVariant,
                    downloadBase: Self.downloadBase,
                    useBackgroundSession: true
                ) { progress in
                    Task { @MainActor in
                        // Progress callbacks arrive off the main actor, so a late one can
                        // land after `.ready` was set and pin the UI at 100% forever.
                        // Only a download still in flight may move the progress.
                        guard case .downloading = self.state else { return }
                        self.state = .downloading(progress.fractionCompleted)
                    }
                }
                UserDefaults.standard.set(folder.path, forKey: Self.modelFolderKey)
                state = .ready
                preload()
            } catch {
                state = .failed(error.localizedDescription)
                throw error
            }
        }
        downloadTask = task
        defer { downloadTask = nil }
        try await task.value
    }

    func deleteModel() {
        pipe = nil
        if let folder = Self.savedModelFolder {
            try? FileManager.default.removeItem(at: folder)
        }
        UserDefaults.standard.removeObject(forKey: Self.modelFolderKey)
        state = .notDownloaded
    }

    /// A segment plus the language whose decoding run produced it.
    private struct PickedSegment {
        let segment: TranscriptionSegment
        let language: String?
    }

    // MARK: - Transcription

    func transcribe(
        audioURL: URL,
        language: TranscriptionLanguage,
        identifySpeakers: Bool = false,
        spokenLanguages: [TranscriptionLanguage] = []
    ) async throws -> String {
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            throw TranscriptionError.audioFileNotFound
        }
        guard let modelFolder = Self.savedModelFolder else {
            throw TranscriptionError.whisperModelNotDownloaded
        }

        defer { progressLabel = nil }

        // Whisper decodes in 30s windows. Window count is the only progress signal
        // the API exposes, and it's close enough to drive a percentage.
        let audioFile = try AVAudioFile(forReading: audioURL)
        let seconds = Double(audioFile.length) / audioFile.fileFormat.sampleRate
        let totalWindows = max(1, Int(ceil(seconds / 30)))

        // On a cold start CoreML has to specialize 626 MB of weights for this chip,
        // which is most of the wait, so it gets its own label.
        progressLabel = pipe == nil ? "Loading model…" : "Transcribing… 0%"

        // No decoder prompt. Whisper's only vocabulary channel is `promptTokens`,
        // and on this device a two-word dictionary cost the end of the transcript
        // and mangled the German in it: the prompt sets a style the decoder imitates
        // and makes it stop early. The dictionary is applied to the finished text
        // instead, in `TranscriptFormatter.applyingVocabulary`.
        let promptTokens: [Int]? = nil

        // The main language plus any additional ones, deduped in order. Two or more
        // means decode once per language and keep the better-scoring run per window:
        // WhisperKit's own detection pass can't be constrained (its language filter
        // is private and it overwrites the language option before custom filters are
        // consulted), so this is the only way to keep a codeswitching recording from
        // being decoded entirely as one language.
        var candidates: [TranscriptionLanguage] = []
        for candidate in ([language] + spokenLanguages) where candidate != .auto {
            if !candidates.contains(candidate) { candidates.append(candidate) }
        }

        // One candidate pins that language even if the main picker says Auto-detect;
        // no candidates leaves detection to the model.
        let effectiveLanguage = candidates.first ?? .auto

        let pipe = try await loadPipe(modelFolder: modelFolder)
        progressLabel = "Transcribing… 0%"

        let picked: [PickedSegment]
        if candidates.count >= 2 {
            picked = try await bestOfSegments(
                languages: candidates,
                pipe: pipe,
                audioPath: audioURL.path,
                promptTokens: promptTokens,
                wordTimestamps: identifySpeakers
            )
        } else {
            picked = try await singleLanguageSegments(
                pipe: pipe,
                audioURL: audioURL,
                language: effectiveLanguage,
                promptTokens: promptTokens,
                wordTimestamps: identifySpeakers,
                totalWindows: totalWindows
            )
        }

        lastReportedPercent = 0

        return try await finish(
            picked: picked,
            audioURL: audioURL,
            identifySpeakers: identifySpeakers
        )
    }

    private func singleLanguageSegments(
        pipe: WhisperKit,
        audioURL: URL,
        language effectiveLanguage: TranscriptionLanguage,
        promptTokens: [Int]?,
        wordTimestamps: Bool,
        totalWindows: Int
    ) async throws -> [PickedSegment] {
        let results = try await pipe.transcribe(
            audioPath: audioURL.path,
            decodeOptions: DecodingOptions(
                language: effectiveLanguage.code,
                usePrefillPrompt: true,
                detectLanguage: effectiveLanguage == .auto,
                skipSpecialTokens: true,
                // Speaker attribution needs per-word timings to line the transcript
                // up against the diarization timeline.
                wordTimestamps: wordTimestamps,
                promptTokens: promptTokens,
                // Whisper invents text over silence, which is where the stray
                // Japanese came from. Suppressing blanks curbs the worst of it.
                suppressBlank: true
                // No `chunkingStrategy: .vad`. VAD splits the audio by voice
                // activity and transcribes each chunk; when a chunk's decode ended
                // early the rest of that chunk was dropped, which is how 51 seconds
                // of speech became 2 segments and 262 characters. Sequential
                // windowing covers the whole file instead.
            ),
            callback: { progress in
                Task { @MainActor in
                    // .vad chunking can complete windows out of order, so never walk back.
                    let fraction = min(1, Double(progress.windowId + 1) / Double(totalWindows))
                    let percent = Int(fraction * 100)
                    if percent >= self.lastReportedPercent {
                        self.lastReportedPercent = percent
                        self.progressLabel = "Transcribing… \(percent)%"
                    }
                }
                // false stops decoding, which is how a cancelled job actually stops
                // burning the Neural Engine instead of just discarding its result.
                return Task.isCancelled ? false : nil
            }
        )
        return results.flatMap { result in
            result.segments.map { PickedSegment(segment: $0, language: result.language) }
        }
    }

    /// Turn the chosen segments into the final transcript, attributing speakers when
    /// asked. Both the single-language and multi-language paths end here, which is
    /// what makes the two features compose: speaker labels used to be unreachable
    /// whenever more than one language was configured.
    private func finish(
        picked: [PickedSegment],
        audioURL: URL,
        identifySpeakers: Bool
    ) async throws -> String {
        let ordered = picked.sorted { $0.segment.start < $1.segment.start }
        let covered = ordered.reduce(0.0) { $0 + Double($1.segment.end - $1.segment.start) }
        lastDiagnostics.append(
            "Transcript built from \(ordered.count) segments, \(ordered.reduce(0) { $0 + $1.segment.text.count }) chars, \(String(format: "%.0f", covered))s covered"
        )

        if identifySpeakers {
            do {
                let labeled = try await speakerLabelled(picked: ordered, audioURL: audioURL)
                if !labeled.isEmpty { return labeled }
            } catch {
                lastDiarizationNote = "Speaker identification failed: \(error.localizedDescription)"
            }
        }

        let text = ordered.map(\.segment.text).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw TranscriptionError.noSpeechDetected
        }
        return text
    }

    /// Whether a challenger says a comparable amount per second to the anchor. A
    /// wrong-language decode tends to emit a handful of words for a long stretch of
    /// speech, and that is the signal that catches it.
    private func isComparablyDense(_ challenger: [PickedSegment], to anchor: PickedSegment) -> Bool {
        let anchorDuration = max(0.1, Double(anchor.segment.end - anchor.segment.start))
        let anchorDensity = Double(anchor.segment.text.count) / anchorDuration

        let challengerDuration = max(0.1, challenger.reduce(0.0) {
            $0 + Double($1.segment.end - $1.segment.start)
        })
        let challengerDensity = challenger.reduce(0) { $0 + $1.segment.text.count } / 1
        return Double(challengerDensity) / challengerDuration >= anchorDensity * 0.6
    }

    /// Attribute each transcript segment to a speaker and group the result into
    /// turns. Returns an empty string for a single speaker, so a monologue reads as
    /// plain prose rather than "Speaker 1:" on every paragraph.
    ///
    /// The mapping is done here rather than with SpeakerKit's `addSpeakerInfo`,
    /// because these segments may come from several decoding runs in different
    /// languages and no longer belong to one `TranscriptionResult`.
    private func speakerLabelled(picked: [PickedSegment], audioURL: URL) async throws -> String {
        progressLabel = "Identifying speakers…"

        let speakerKit = try await loadSpeakerKit()
        let audioArray = try AudioProcessor.loadAudioAsFloatArray(fromPath: audioURL.path)
        let diarization = try await speakerKit.diarize(audioArray: audioArray)

        guard diarization.speakerCount > 1 else {
            lastDiarizationNote = "Speaker identification found 1 speaker, labels omitted"
            return ""
        }
        lastDiarizationNote = "Speaker identification found \(diarization.speakerCount) speakers"

        var turns: [SpeakerTurn] = []
        // Confidence of a merged turn is the mean over the segments that formed it,
        // so a long turn isn't judged by its shakiest sentence.
        var confidenceSums: [Float] = []
        var confidenceCounts: [Int] = []

        // Attribute per word, not per segment. Whisper draws segment boundaries on
        // pauses, so a single segment routinely contains two people ("...this will
        // be the first speaker 10 years at netflix..."), and a whole-segment label
        // has to pick one of them. Word timings put the boundary where the speaker
        // actually changes.
        for unit in attributionUnits(from: picked) {
            let text = unit.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let speaker = dominantSpeaker(
                from: unit.start,
                to: unit.end,
                in: diarization
            ) ?? turns.last?.speaker
            // Consecutive segments from one speaker are one turn; diarization splits
            // on pauses, which would otherwise label every sentence separately.
            if let last = turns.last, last.speaker == speaker {
                let index = turns.count - 1
                confidenceSums[index] += unit.confidence
                confidenceCounts[index] += 1
                turns[index] = SpeakerTurn(
                    speaker: speaker,
                    start: last.start,
                    end: TimeInterval(unit.end),
                    text: joined(last.text, with: text),
                    // A turn keeps the language it started in; a switch mid-turn is
                    // rare because diarization splits on the pause anyway.
                    language: last.language,
                    confidence: confidenceSums[index] / Float(confidenceCounts[index])
                )
            } else {
                confidenceSums.append(unit.confidence)
                confidenceCounts.append(1)
                turns.append(SpeakerTurn(
                    speaker: speaker,
                    start: TimeInterval(unit.start),
                    end: TimeInterval(unit.end),
                    text: text,
                    language: unit.owner.language,
                    confidence: unit.confidence
                ))
            }
        }

        lastDiagnostics.append("Grouped into \(turns.count) speaker turns, \(turns.reduce(0) { $0 + $1.text.count }) chars")

        guard turns.count > 1 else { return "" }

        let distances = pairDistances(in: diarization)

        lastSpeakerAnalysis = SpeakerAnalysis(
            speakerCount: Set(turns.compactMap(\.speaker)).count,
            turns: turns,
            pairDistances: distances
        )

        // Cluster ids are arbitrary and sparse: printing them raw gave "Speaker 1"
        // and "Speaker 3" with no 2. Number by order of first appearance instead.
        var displayNumbers: [Int: Int] = [:]
        for turn in turns {
            guard let id = turn.speaker, displayNumbers[id] == nil else { continue }
            displayNumbers[id] = displayNumbers.count + 1
        }

        return turns
            .map { turn in
                let label = turn.speaker.flatMap { displayNumbers[$0] }
                    .map { "Speaker \($0)" } ?? "Unknown speaker"
                return "\(label): \(turn.text)"
            }
            .joined(separator: "\n\n")
    }

    /// Word timings include their own leading space; segment text does not.
    private func joined(_ existing: String, with next: String) -> String {
        existing.hasSuffix(" ") || next.hasPrefix(" ")
            ? existing + next
            : existing + " " + next
    }

    /// The smallest piece of transcript that can carry its own speaker label: one
    /// word when timings are available, otherwise the whole segment.
    private struct AttributionUnit {
        let text: String
        let start: Float
        let end: Float
        let confidence: Float
        let owner: PickedSegment
    }

    /// Split segments into words where Whisper gave timings. Without word
    /// timestamps a segment stays whole, which is the old behaviour and the reason
    /// two speakers inside one segment shared a label.
    private func attributionUnits(from picked: [PickedSegment]) -> [AttributionUnit] {
        picked.flatMap { item -> [AttributionUnit] in
            guard let words = item.segment.words, !words.isEmpty else {
                return [AttributionUnit(
                    text: item.segment.text,
                    start: item.segment.start,
                    end: item.segment.end,
                    confidence: item.segment.avgLogprob,
                    owner: item
                )]
            }
            return words.map { word in
                AttributionUnit(
                    text: word.word,
                    start: word.start,
                    end: word.end,
                    // Word probability is a different scale to segment avgLogprob;
                    // the segment's score stays the honest per-turn confidence.
                    confidence: item.segment.avgLogprob,
                    owner: item
                )
            }
        }
    }

    /// Whoever speaks for the longest inside this stretch.
    ///
    /// Was a midpoint lookup, which failed constantly: a midpoint that lands in a
    /// pause between diarization segments matches nothing, and overlapping speech
    /// comes back as `.multiple`, whose `speakerId` is nil. Both produced "Unknown
    /// speaker" on ordinary conversation. Overlap duration uses every diarization
    /// segment that touches the stretch, and counts each participant of overlapping
    /// speech.
    private func dominantSpeaker(
        from start: Float,
        to end: Float,
        in diarization: DiarizationResult
    ) -> Int? {
        var talkTime: [Int: Float] = [:]

        for segment in diarization.segments {
            let overlap = min(end, segment.endTime) - max(start, segment.startTime)
            guard overlap > 0 else { continue }

            switch segment.speaker {
            case .speakerId(let id):
                talkTime[id, default: 0] += overlap
            case .multiple(let ids):
                // Split the credit; whoever else also spoke here still gets counted.
                for id in ids {
                    talkTime[id, default: 0] += overlap / Float(ids.count)
                }
            case .noMatch:
                continue
            }
        }

        return talkTime.max { $0.value < $1.value }?.key
    }

    /// Cosine distance for every speaker pair. Naming the pairs, rather than only
    /// the closest distance, is what lets a consumer act: it can merge the two
    /// labels that are close instead of knowing only that some pair is.
    private func pairDistances(in diarization: DiarizationResult) -> [SpeakerPairDistance] {
        let ids = diarization.speakerCentroidEmbeddings.keys.sorted()
        var pairs: [SpeakerPairDistance] = []
        for (index, a) in ids.enumerated() {
            for b in ids.dropFirst(index + 1) {
                guard let distance = diarization.centroidCosineDistance(between: a, and: b) else { continue }
                pairs.append(SpeakerPairDistance(speakers: [a + 1, b + 1], distance: distance))
            }
        }
        return pairs.sorted { $0.distance < $1.distance }
    }

    /// Decode the audio once per candidate language, then let the extra languages
    /// override individual sentences of the main language's transcript.
    ///
    /// The main language's run defines the timeline, so coverage is exactly what a
    /// single-language transcription would have produced and nothing can go
    /// missing. For each of its segments a competing language wins that stretch
    /// only if its overlapping audio scored better.
    ///
    /// Selecting greedily across all runs by confidence, which is what this did
    /// before, was unsound: a wrong-language decode is often short and *confident*,
    /// so it won long stretches and deleted the correct text underneath it.
    ///
    /// Cost is one full decode per language. Fine for two; don't offer ten.
    private func bestOfSegments(
        languages: [TranscriptionLanguage],
        pipe: WhisperKit,
        audioPath: String,
        promptTokens: [Int]?,
        wordTimestamps: Bool
    ) async throws -> [PickedSegment] {
        var runs: [[PickedSegment]] = []

        for (index, language) in languages.enumerated() {
            // Deliberately generic. "Transcribing… English (1/3)" exposed an
            // internal decoding pass and read like an error when the recording
            // wasn't English.
            let overall = Int(Double(index) / Double(languages.count) * 100)
            progressLabel = "Transcribing… \(overall)%"
            let results = try await pipe.transcribe(
                audioPath: audioPath,
                decodeOptions: DecodingOptions(
                    language: language.code,
                    usePrefillPrompt: true,
                    detectLanguage: false,
                    skipSpecialTokens: true,
                    wordTimestamps: wordTimestamps,
                    promptTokens: promptTokens,
                    suppressBlank: true
                )
            )
            runs.append(results.flatMap { result in
                result.segments.map { PickedSegment(segment: $0, language: result.language) }
            })
        }

        for (index, run) in runs.enumerated() {
            let chars = run.reduce(0) { $0 + $1.segment.text.count }
            let covered = run.reduce(0.0) { $0 + Double($1.segment.end - $1.segment.start) }
            lastDiagnostics.append(
                "Decoded \(languages[index].rawValue): \(run.count) segments, \(chars) chars, \(String(format: "%.0f", covered))s covered"
            )
        }

        guard let reference = runs.first else { return [] }
        let challengers = runs.dropFirst()
        var chosen: [PickedSegment] = []
        var replacedStretches = 0

        for anchor in reference {
            guard !anchor.segment.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }

            var best = (score: anchor.segment.avgLogprob, picks: [anchor])

            // Only consider replacing this stretch when the main language actually
            // struggled with it. Confidence is not comparable across languages: a
            // wrong-language decode of clear English is often a *short, confident*
            // hallucination, so on raw score it beat the correct text and the
            // transcript lost whole sentences.
            if anchor.segment.avgLogprob < Self.strugglingScore {
                for challenger in challengers {
                    let overlapping = challenger.filter {
                        $0.segment.start < anchor.segment.end && $0.segment.end > anchor.segment.start
                    }
                    guard !overlapping.isEmpty else { continue }

                    let score = overlapping
                        .map(\.segment.avgLogprob)
                        .reduce(0, +) / Float(overlapping.count)
                    // Beat the anchor by a margin, not by a hair.
                    guard score > best.score + Self.winningMargin else { continue }
                    // And say a comparable amount: a challenger with a fraction of
                    // the words is hallucinating, however confident it sounds.
                    guard isComparablyDense(overlapping, to: anchor) else { continue }

                    best = (score, overlapping)
                }
            }

            if best.picks.first?.language != anchor.language {
                replacedStretches += 1
                let swapped = best.picks.reduce(0) { $0 + $1.segment.text.count }
                        lastDiagnostics.append("Swapped \(String(format: "%.0f", anchor.segment.start))-\(String(format: "%.0f", anchor.segment.end))s: \(anchor.segment.text.count) chars \(anchor.language ?? "?") to \(swapped) chars \(best.picks.first?.language ?? "?")")
            }
            chosen.append(contentsOf: best.picks)
        }

        if replacedStretches > 0 {
            lastDiagnostics.append("\(replacedStretches) stretch\(replacedStretches == 1 ? "" : "es") transcribed in another language")
        }

        lastDiagnostics.append("Kept \(chosen.count) segments, \(chosen.reduce(0) { $0 + $1.segment.text.count }) chars")

        // A challenger's segments can span two anchors, so the same stretch could
        // otherwise be appended twice.
        var seen: Set<String> = []
        return chosen
            .filter { seen.insert("\($0.segment.start)-\($0.segment.end)-\($0.segment.text)").inserted }
            .sorted { $0.segment.start < $1.segment.start }
    }

    private func loadSpeakerKit() async throws -> SpeakerKit {
        if let speakerKit { return speakerKit }
        // Pyannote's weights are a separate download (a few tens of MB), fetched on
        // first use rather than alongside the 626 MB Whisper model.
        let created = try await SpeakerKit(PyannoteConfig(download: true, load: true))
        speakerKit = created
        return created
    }

    /// How long the last cold model load took, in seconds. Nil until one happens.
    /// Recorded so a slow first transcription can be attributed to CoreML
    /// specialization rather than guessed at.
    private var lastModelLoadSeconds: TimeInterval?

    /// Read the cold-load duration once and clear it, so only the transcription
    /// that actually paid for the load gets the log entry.
    func consumeLastModelLoadSeconds() -> TimeInterval? {
        defer { lastModelLoadSeconds = nil }
        return lastModelLoadSeconds
    }

    /// What diarization actually did on the last run, for the activity log. Errors
    /// used to be swallowed, which made "no speaker labels" indistinguishable from
    /// "diarization never ran".
    private var lastDiarizationNote: String?

    /// Diagnostics for the activity log: where text came from and how much of it
    /// survived each stage. The console can't be relied on with an IPA install, so
    /// the numbers go somewhere they can be read on the device.
    private var lastDiagnostics: [String] = []

    func consumeLastDiagnostics() -> [String] {
        defer { lastDiagnostics = [] }
        return lastDiagnostics
    }

    /// Structured diarization output for the last transcription, for the webhook.
    private var lastSpeakerAnalysis: SpeakerAnalysis?

    func consumeLastSpeakerAnalysis() -> SpeakerAnalysis? {
        defer { lastSpeakerAnalysis = nil }
        return lastSpeakerAnalysis
    }

    func consumeLastDiarizationNote() -> String? {
        defer { lastDiarizationNote = nil }
        return lastDiarizationNote
    }

    /// Serialized on purpose. `preload()` at launch and a transcription starting
    /// moments later both used to see `pipe == nil` and each build a WhisperKit,
    /// so 626 MB of weights got specialized twice at once, competing for the
    /// Neural Engine and memory.
    private func loadPipe(modelFolder: URL) async throws -> WhisperKit {
        if let pipe { return pipe }
        if let loadTask { return try await loadTask.value }

        let task = Task { () throws -> WhisperKit in
            try await self.buildPipe(modelFolder: modelFolder)
        }
        loadTask = task
        defer { loadTask = nil }

        let created = try await task.value
        pipe = created
        return created
    }

    private func buildPipe(modelFolder: URL) async throws -> WhisperKit {
        let startedAt = Date()
        let config = WhisperKitConfig(
            model: Self.modelVariant,
            downloadBase: Self.downloadBase,
            modelFolder: modelFolder.path,
            verbose: false,
            logLevel: .error,
            prewarm: false,
            load: true,
            download: false
        )
        let created = try await WhisperKit(config)
        lastModelLoadSeconds = Date().timeIntervalSince(startedAt)
        print("[Whisper] model loaded in \(String(format: "%.1f", lastModelLoadSeconds ?? 0))s")
        return created
    }
}
