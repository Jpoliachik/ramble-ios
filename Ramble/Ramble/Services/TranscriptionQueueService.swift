//
//  TranscriptionQueueService.swift
//  Ramble
//

import Combine
import Foundation

@MainActor
final class TranscriptionQueueService: ObservableObject {
    static let shared = TranscriptionQueueService()

    @Published private(set) var isProcessing = false

    var hasActiveWork: Bool {
        isProcessing || !queue.isEmpty
    }

    private let speechAnalyzer = SpeechAnalyzerTranscriptionService()
    private let legacySpeech = LegacySpeechTranscriptionService()
    private let proxyService = ProxyTranscriptionService()
    private let localWhisper = LocalWhisperTranscriptionService.shared
    private let storageService = StorageService.shared
    private let settingsService = SettingsService.shared
    private var queue: [TranscriptionJob] = []
    /// The in-flight job, so it can be cancelled from the UI.
    private var currentTask: Task<Void, Never>?
    private var processingRecordingId: UUID?
    private let queueFile = StorageService.documentsDirectory
        .appendingPathComponent("transcription_queue.json")

    private init() {
        loadQueue()
    }

    // MARK: - Public API

    func enqueue(recordingId: UUID) {
        // Don't double-enqueue, and don't queue a second job behind one that is
        // already running for this recording: that produced two transcriptions of
        // the same audio, two model loads and duplicate activity entries.
        guard !queue.contains(where: { $0.recordingId == recordingId }),
              processingRecordingId != recordingId
        else { return }
        let settings = settingsService.load()
        let cloudModel: CloudModel? = settings.transcriptionProvider.isCloud ? settings.cloudModel : nil
        let job = TranscriptionJob(
            recordingId: recordingId,
            provider: settings.transcriptionProvider,
            cloudModel: cloudModel
        )
        queue.append(job)
        saveQueue()
        processNextIfNeeded()
    }

    /// Whether this recording is waiting in the queue or being worked on, so the
    /// UI can disable an action that would do nothing.
    func isQueued(recordingId: UUID) -> Bool {
        queue.contains { $0.recordingId == recordingId } || processingRecordingId == recordingId
    }

    func processNextIfNeeded() {
        guard !isProcessing, let job = queue.first else { return }
        // Belt and braces against the same recording being picked up twice.
        guard job.recordingId != processingRecordingId else { return }
        processJob(job)
    }

    func resumePendingJobs() {
        // Re-enqueue any recordings stuck in recorded/transcribing state
        let recordings = storageService.loadRecordings()
        for recording in recordings {
            if recording.status == .recorded || recording.status == .transcribing {
                enqueue(recordingId: recording.id)
            }
        }
        processNextIfNeeded()
    }

    /// Download the speech model and retry all recordings that failed due to missing model.
    func downloadModelAndRetryPending() async throws {
        log(message: "Speech model download started")
        do {
            try await speechAnalyzer.downloadModel()
            log(message: "Speech model downloaded")
        } catch {
            log(message: "Speech model download failed — \(error.localizedDescription)")
            throw error
        }

        let recordings = storageService.loadRecordings()
        for recording in recordings where recording.isModelNotInstalled {
            retry(recordingId: recording.id)
        }
    }

    /// Proactively prepare the speech model on app launch.
    func prepareModelIfNeeded() async {
        await speechAnalyzer.prepareModelIfNeeded()
    }

    /// Manually retry a failed recording by re-enqueuing it.
    /// Returns false if the cloud transcription limit has been reached.
    @discardableResult
    func retry(recordingId: UUID) -> Bool {
        var recordings = storageService.loadRecordings()
        guard let idx = recordings.firstIndex(where: { $0.id == recordingId }) else { return false }

        let settings = settingsService.load()
        if settings.transcriptionProvider.isCloud
            && recordings[idx].cloudTranscriptionCount >= TranscriptionJob.maxCloudTranscriptions {
            return false
        }

        recordings[idx].status = .recorded
        recordings[idx].lastError = nil
        recordings[idx].activityLog.append(ActivityEntry("Manual retry requested"))
        storageService.saveRecordings(recordings)

        // Remove any existing job for this recording before re-enqueuing, and stop
        // a run that's already going, so a retry replaces it instead of adding a
        // second pass over the same audio.
        queue.removeAll { $0.recordingId == recordingId }
        saveQueue()

        if processingRecordingId == recordingId {
            currentTask?.cancel()
            currentTask = nil
            processingRecordingId = nil
            isProcessing = false
        }

        enqueue(recordingId: recordingId)
        return true
    }

    // MARK: - Job Processing

    private func processJob(_ job: TranscriptionJob) {
        isProcessing = true
        processingRecordingId = job.recordingId

        currentTask = Task {
            await processTranscription(job)
            processingRecordingId = nil
        }
    }

    /// Stop transcribing this recording now and leave it retryable.
    ///
    /// Marked failed rather than back to `.recorded`, because `resumePendingJobs`
    /// re-enqueues anything still in `.recorded` and would restart the very work
    /// the user just stopped.
    func cancelTranscription(recordingId: UUID) {
        queue.removeAll { $0.recordingId == recordingId }
        saveQueue()

        if processingRecordingId == recordingId {
            currentTask?.cancel()
            currentTask = nil
            processingRecordingId = nil
            isProcessing = false
        }

        var recordings = storageService.loadRecordings()
        if let idx = recordings.firstIndex(where: { $0.id == recordingId }) {
            recordings[idx].status = .failed
            recordings[idx].lastError = "Transcription cancelled"
            recordings[idx].activityLog.append(ActivityEntry("Transcription cancelled"))
            storageService.saveRecordings(recordings)
        }

        processNextIfNeeded()
    }

    private func providerLabel(for job: TranscriptionJob) -> String {
        if let model = job.cloudModel {
            return model.displayName
        }
        return job.provider.displayName
    }

    private func processTranscription(_ job: TranscriptionJob) async {
        var recordings = storageService.loadRecordings()
        guard let idx = recordings.firstIndex(where: { $0.id == job.recordingId }) else {
            removeJob(job)
            isProcessing = false
            processNextIfNeeded()
            return
        }

        // Update status to transcribing. The log entry is what makes the gap between
        // capture and completion readable after the fact.
        recordings[idx].status = .transcribing
        var startedNote = "Transcription started via \(providerLabel(for: job))"
        if job.provider == .localWhisper {
            // Spell out the toggles, so a missing speaker label is never ambiguous
            // between "diarization found one speaker" and "it never ran".
            let settings = settingsService.load()
            startedNote += " · speakers \(settings.identifySpeakers ? "on" : "off")"
            let extra = settings.effectiveAdditionalLanguages
            if !extra.isEmpty {
                startedNote += " · +\(extra.map(\.rawValue).joined(separator: ","))"
            }
        }
        recordings[idx].activityLog.append(ActivityEntry(startedNote))
        storageService.saveRecordings(recordings)

        let audioURL = recordings[idx].audioFileURL
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            recordings[idx].status = .failed
            recordings[idx].lastError = "Audio file not found"
            storageService.saveRecordings(recordings)
            removeJob(job)
            isProcessing = false
            processNextIfNeeded()
            return
        }

        // Too short to hold speech: fail before anything loads a model or opens a
        // network connection. The capture-time guard doesn't cover watch recordings,
        // recordings saved by older builds, or a manual retry on this screen.
        if recordings[idx].duration < Constants.Recording.minimumTranscribableDuration {
            recordings[idx].status = .failed
            recordings[idx].lastError = "Recording too short"
            recordings[idx].activityLog.append(
                ActivityEntry("Too short to transcribe — skipped")
            )
            storageService.saveRecordings(recordings)
            removeJob(job)
            isProcessing = false
            processNextIfNeeded()
            return
        }

        // Block if this recording has exhausted its cloud transcription limit
        if job.provider.isCloud
            && recordings[idx].cloudTranscriptionCount >= TranscriptionJob.maxCloudTranscriptions {
            recordings[idx].status = .failed
            recordings[idx].lastError = "Cloud transcription limit reached (\(TranscriptionJob.maxCloudTranscriptions))"
            recordings[idx].activityLog.append(
                ActivityEntry("Blocked — \(providerLabel(for: job)) cloud transcription limit reached (\(TranscriptionJob.maxCloudTranscriptions) uses)")
            )
            storageService.saveRecordings(recordings)
            removeJob(job)
            isProcessing = false
            processNextIfNeeded()
            return
        }

        do {
            var rawText: String
            var speakerAnalysis: SpeakerAnalysis?
            if job.provider.isCloud {
                // Fetch fresh JWS at call time (not enqueue time) — tokens expire
                let jws = SubscriptionService.shared.currentJWSTransaction
                let currentSettings = settingsService.load()
                let request = ProxyTranscriptionRequest(
                    audioURL: audioURL,
                    model: job.cloudModel ?? .whisperLargeV3Turbo,
                    language: currentSettings.transcriptionLanguage,
                    customVocabulary: currentSettings.effectiveVocabulary,
                    removeFillerWords: currentSettings.removeFillerWords,
                    jwsTransaction: jws
                )
                rawText = try await proxyService.transcribe(request)
            } else if job.provider == .localWhisper {
                let currentSettings = settingsService.load()
                let local = try await localWhisper.transcribe(
                    audioURL: audioURL,
                    language: currentSettings.transcriptionLanguage,
                    identifySpeakers: currentSettings.identifySpeakers,
                    spokenLanguages: currentSettings.effectiveAdditionalLanguages
                )
                rawText = TranscriptFormatter.paragraphs(from: local)

                // Dictionary terms are corrected after decoding, by Apple's
                // on-device model. Prompting Whisper with them cost whole
                // sentences, so the finished text gets reviewed instead. No extra
                // switch: having a dictionary is the switch.
                let vocabulary = currentSettings.effectiveVocabulary
                if !vocabulary.isEmpty {
                    let corrections = await AppleIntelligenceService.vocabularyCorrections(
                        in: rawText,
                        terms: vocabulary
                    )
                    for correction in corrections {
                        rawText = rawText.replacingOccurrences(
                            of: correction.heard,
                            with: correction.correct,
                            options: [.caseInsensitive]
                        )
                    }
                    if !corrections.isEmpty {
                        let described = corrections
                            .map { "\($0.heard) to \($0.correct)" }
                            .joined(separator: ", ")
                        var withNote = storageService.loadRecordings()
                        if let i = withNote.firstIndex(where: { $0.id == job.recordingId }) {
                            withNote[i].activityLog.append(
                                ActivityEntry("Dictionary corrected \(described)")
                            )
                            storageService.saveRecordings(withNote)
                        }
                    }
                }
                if currentSettings.removeFillerWords {
                    rawText = TranscriptFormatter.removingFillerWords(from: rawText)
                }
                speakerAnalysis = localWhisper.consumeLastSpeakerAnalysis()
                let diagnostics = localWhisper.consumeLastDiagnostics()
                if !diagnostics.isEmpty {
                    var withNotes = storageService.loadRecordings()
                    if let i = withNotes.firstIndex(where: { $0.id == job.recordingId }) {
                        for line in diagnostics {
                            withNotes[i].activityLog.append(ActivityEntry(line))
                        }
                        storageService.saveRecordings(withNotes)
                    }
                }
                if let note = localWhisper.consumeLastDiarizationNote() {
                    var withNote = storageService.loadRecordings()
                    if let i = withNote.firstIndex(where: { $0.id == job.recordingId }) {
                        withNote[i].activityLog.append(ActivityEntry(note))
                        storageService.saveRecordings(withNote)
                    }
                }
                if let loadSeconds = localWhisper.consumeLastModelLoadSeconds() {
                    // Attribution for a slow transcript: cold model load or decoding.
                    var withLoad = storageService.loadRecordings()
                    if let i = withLoad.firstIndex(where: { $0.id == job.recordingId }) {
                        withLoad[i].activityLog.append(
                            ActivityEntry("Whisper model loaded in \(String(format: "%.1f", loadSeconds))s")
                        )
                        storageService.saveRecordings(withLoad)
                    }
                }
            } else if #available(iOS 26.0, *) {
                // Cloud transcripts come back paragraphed from the proxy;
                // on-device output is one block, so group it here for parity.
                let onDevice = try await speechAnalyzer.transcribe(audioURL: audioURL)
                rawText = TranscriptFormatter.paragraphs(from: onDevice)
                if settingsService.load().removeFillerWords {
                    rawText = TranscriptFormatter.removingFillerWords(from: rawText)
                }
            } else {
                let onDevice = try await legacySpeech.transcribe(audioURL: audioURL)
                rawText = TranscriptFormatter.paragraphs(from: onDevice)
                if settingsService.load().removeFillerWords {
                    rawText = TranscriptFormatter.removingFillerWords(from: rawText)
                }
            }
            if Task.isCancelled {
                isProcessing = false
                return
            }

            let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)

            // Success — update recording
            var updatedRecordings = storageService.loadRecordings()
            if let i = updatedRecordings.firstIndex(where: { $0.id == job.recordingId }) {
                updatedRecordings[i].status = .completed
                updatedRecordings[i].transcription = text
                updatedRecordings[i].speakerAnalysis = speakerAnalysis
                updatedRecordings[i].lastError = nil
                if job.provider.isCloud {
                    updatedRecordings[i].cloudTranscriptionCount += 1
                }
                updatedRecordings[i].activityLog.append(
                    ActivityEntry("Transcription completed via \(providerLabel(for: job))", httpStatus: job.provider.isCloud ? 200 : nil)
                )
                storageService.saveRecordings(updatedRecordings)
            }

            removeJob(job)
            isProcessing = false

            // Enqueue webhook if a destination is configured
            if settingsService.load().isWebhookConfigured {
                WebhookQueueService.shared.enqueue(recordingId: job.recordingId)
            }

            processNextIfNeeded()

        } catch TranscriptionError.subscriptionRequired {
            // Subscription missing or expired — fail immediately, don't retry
            var updatedRecordings = storageService.loadRecordings()
            if let idx = updatedRecordings.firstIndex(where: { $0.id == job.recordingId }) {
                updatedRecordings[idx].status = .failed
                updatedRecordings[idx].lastError = TranscriptionError.subscriptionRequired.localizedDescription
                updatedRecordings[idx].activityLog.append(
                    ActivityEntry("Transcription failed via \(providerLabel(for: job)) — premium subscription required", httpStatus: 403)
                )
                storageService.saveRecordings(updatedRecordings)
            }
            removeJob(job)
            isProcessing = false
            processNextIfNeeded()

        } catch TranscriptionError.modelNotInstalled {
            // Model not downloaded — fail immediately, don't retry
            var updatedRecordings = storageService.loadRecordings()
            if let idx = updatedRecordings.firstIndex(where: { $0.id == job.recordingId }) {
                updatedRecordings[idx].status = .failed
                updatedRecordings[idx].lastError = TranscriptionError.modelNotInstalled.localizedDescription
                updatedRecordings[idx].activityLog.append(
                    ActivityEntry("Transcription failed via \(providerLabel(for: job)) — speech model not downloaded")
                )
                storageService.saveRecordings(updatedRecordings)
            }
            removeJob(job)
            isProcessing = false
            processNextIfNeeded()

        } catch TranscriptionError.whisperModelNotDownloaded {
            // Whisper weights missing — fail immediately, don't retry
            var updatedRecordings = storageService.loadRecordings()
            if let idx = updatedRecordings.firstIndex(where: { $0.id == job.recordingId }) {
                updatedRecordings[idx].status = .failed
                updatedRecordings[idx].lastError = TranscriptionError.whisperModelNotDownloaded.localizedDescription
                updatedRecordings[idx].activityLog.append(
                    ActivityEntry("Transcription failed via \(providerLabel(for: job)) — Whisper model not downloaded")
                )
                storageService.saveRecordings(updatedRecordings)
            }
            removeJob(job)
            isProcessing = false
            processNextIfNeeded()

        } catch TranscriptionError.noSpeechDetected {
            // One retry, then terminal. Silence stays silent however many times it's
            // decoded, so five attempts times three languages was waste. But a file
            // read before it finished being written also reports no speech, and that
            // one is worth a second look.
            if job.retryCount == 0 {
                var updatedRecordings = storageService.loadRecordings()
                if let idx = updatedRecordings.firstIndex(where: { $0.id == job.recordingId }) {
                    updatedRecordings[idx].status = .recorded
                    updatedRecordings[idx].activityLog.append(
                        ActivityEntry("No speech detected, retrying once")
                    )
                    storageService.saveRecordings(updatedRecordings)
                }
                var retried = job
                retried.retryCount = 1
                updateJob(retried)
                isProcessing = false
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                processNextIfNeeded()
                return
            }

            var updatedRecordings = storageService.loadRecordings()
            if let idx = updatedRecordings.firstIndex(where: { $0.id == job.recordingId }) {
                updatedRecordings[idx].status = .failed
                updatedRecordings[idx].lastError = TranscriptionError.noSpeechDetected.localizedDescription
                updatedRecordings[idx].activityLog.append(
                    ActivityEntry("Transcription failed via \(providerLabel(for: job)) — no speech detected")
                )
                storageService.saveRecordings(updatedRecordings)
            }
            removeJob(job)
            isProcessing = false
            processNextIfNeeded()

        } catch TranscriptionError.localeNotSupported {
            // Locale not supported — fail immediately, don't retry (permanent condition)
            var updatedRecordings = storageService.loadRecordings()
            if let idx = updatedRecordings.firstIndex(where: { $0.id == job.recordingId }) {
                updatedRecordings[idx].status = .failed
                updatedRecordings[idx].lastError = TranscriptionError.localeNotSupported.localizedDescription
                updatedRecordings[idx].activityLog.append(
                    ActivityEntry("Transcription failed via \(providerLabel(for: job)) — \(TranscriptionError.localeNotSupported.localizedDescription)")
                )
                storageService.saveRecordings(updatedRecordings)
            }
            removeJob(job)
            isProcessing = false
            processNextIfNeeded()

        } catch TranscriptionError.speechAnalyzerUnavailable {
            // iOS version too old for SpeechAnalyzer — fail immediately, don't retry
            var updatedRecordings = storageService.loadRecordings()
            if let idx = updatedRecordings.firstIndex(where: { $0.id == job.recordingId }) {
                updatedRecordings[idx].status = .failed
                updatedRecordings[idx].lastError = TranscriptionError.speechAnalyzerUnavailable.localizedDescription
                updatedRecordings[idx].activityLog.append(
                    ActivityEntry("Transcription failed via \(providerLabel(for: job)) — \(TranscriptionError.speechAnalyzerUnavailable.localizedDescription)")
                )
                storageService.saveRecordings(updatedRecordings)
            }
            removeJob(job)
            isProcessing = false
            processNextIfNeeded()

        } catch let transcriptionError as TranscriptionError {
            var httpStatus: Int?
            if case .proxyError(let code, _) = transcriptionError {
                httpStatus = code
            }
            await handleTranscriptionFailure(job: job, error: transcriptionError.localizedDescription, httpStatus: httpStatus)

        } catch {
            await handleTranscriptionFailure(job: job, error: error.localizedDescription)
        }
    }

    private func handleTranscriptionFailure(job: TranscriptionJob, error: String, httpStatus: Int? = nil) async {
        var updatedJob = job
        updatedJob.retryCount += 1

        var recordings = storageService.loadRecordings()
        if let idx = recordings.firstIndex(where: { $0.id == job.recordingId }) {
            recordings[idx].lastError = error
            if updatedJob.retryCount >= TranscriptionJob.maxRetries {
                recordings[idx].status = .failed
                recordings[idx].activityLog.append(
                    ActivityEntry("Transcription failed via \(providerLabel(for: job)) after \(TranscriptionJob.maxRetries) attempts — \(error)", httpStatus: httpStatus)
                )
                storageService.saveRecordings(recordings)
                removeJob(job)
            } else {
                recordings[idx].status = .recorded
                let delay = updatedJob.retryDelaySeconds
                updatedJob.nextRetryAt = Date().addingTimeInterval(delay)
                recordings[idx].activityLog.append(
                    ActivityEntry("Transcription failed via \(providerLabel(for: job)) — \(error) (attempt \(updatedJob.retryCount)/\(TranscriptionJob.maxRetries), retry in \(Int(delay))s)", httpStatus: httpStatus)
                )
                storageService.saveRecordings(recordings)
                updateJob(updatedJob)
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }

        isProcessing = false
        processNextIfNeeded()
    }

    // MARK: - Activity Log Helper

    /// Log an activity entry for model download events (not tied to a specific recording)
    private func log(message: String) {
        // Model download events apply to all model-not-installed recordings
        var recordings = storageService.loadRecordings()
        var changed = false
        for i in recordings.indices where recordings[i].isModelNotInstalled {
            recordings[i].activityLog.append(ActivityEntry(message))
            changed = true
        }
        if changed {
            storageService.saveRecordings(recordings)
        }
    }

    // MARK: - Queue Persistence

    private func removeJob(_ job: TranscriptionJob) {
        queue.removeAll { $0.id == job.id }
        saveQueue()
    }

    private func updateJob(_ job: TranscriptionJob) {
        if let index = queue.firstIndex(where: { $0.id == job.id }) {
            queue[index] = job
            saveQueue()
        }
    }

    private func loadQueue() {
        guard FileManager.default.fileExists(atPath: queueFile.path),
              let data = try? Data(contentsOf: queueFile),
              let jobs = try? JSONDecoder().decode([TranscriptionJob].self, from: data) else {
            return
        }
        queue = jobs
    }

    private func saveQueue() {
        guard let data = try? JSONEncoder().encode(queue) else { return }
        try? data.write(to: queueFile)
    }
}
