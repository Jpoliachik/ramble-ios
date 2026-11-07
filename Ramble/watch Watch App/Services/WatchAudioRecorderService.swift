//
//  WatchAudioRecorderService.swift
//  watch Watch App
//
//  Recording has to feel instant, so the slow setup (audio category, file,
//  encoder) happens in `prewarm()` before the tap. A tap then only activates
//  the session and starts the recorder that's already waiting.
//

import AVFoundation
import Combine
import Foundation

enum WatchAudioRecorderError: Error {
    case couldNotStart
}

@MainActor
final class WatchAudioRecorderService: NSObject, ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var currentDuration: TimeInterval = 0
    @Published private(set) var audioLevel: Float = 0

    /// Called when something other than the user ended the recording: a phone
    /// call, Siri, an alarm, the 60-minute cap, or the recorder stopping on its own. The audio
    /// captured so far is still good and should be saved.
    var onEndedBySystem: (() -> Void)?

    private var audioRecorder: AVAudioRecorder?
    /// Built and prepared ahead of time so a tap doesn't wait on file and
    /// encoder setup. Used at most once.
    private var preparedRecorder: AVAudioRecorder?
    private var isCategoryConfigured = false
    private var recordingStartTime: Date?
    private var timer: Timer?
    private(set) var currentRecordingURL: URL?

    /// Prepared files that were never recorded into are only a header.
    /// Anything smaller than this, not queued and not in use, is cleanup.
    private static let emptyFileThreshold = 8 * 1024

    /// The longest a note can be. The recorder stops itself here too, so
    /// the cap holds even if the app's timer is held back.
    static let maxDuration: TimeInterval = 60 * 60

    /// Mono AAC at 16 kHz with a pinned bitrate, so a full hour stays under
    /// 15 MB (24 kbps is about 10.8 MB an hour). The later entries are
    /// fallbacks in case the encoder refuses a bitrate on some watch; each
    /// stays at or under 32 kbps.
    private static let settingsOptions: [[String: Any]] = [
        [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 24000
        ],
        [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 32000
        ],
        [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.low.rawValue
        ]
    ]

    private static var documentsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    override init() {
        super.init()
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            MainActor.assumeIsolated {
                guard rawType == AVAudioSession.InterruptionType.began.rawValue else { return }
                self?.endedBySystem()
            }
        }
    }

    // MARK: - Prewarm

    /// Does everything that doesn't need the mic yet. Cheap to call often;
    /// it only builds a recorder when none is waiting. Doesn't activate the
    /// session, so it never interrupts music or other audio.
    func prewarm() {
        guard !isRecording else { return }
        try? configureCategoryIfNeeded()
        if preparedRecorder == nil {
            preparedRecorder = makePreparedRecorder()
        }
    }

    /// Always the watch's own mic. No Bluetooth options: routing to AirPods
    /// means an HFP negotiation that can take a second or more on every start.
    private func configureCategoryIfNeeded() throws {
        guard !isCategoryConfigured else { return }
        try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .default)
        isCategoryConfigured = true
    }

    private func makePreparedRecorder() -> AVAudioRecorder? {
        let url = Self.documentsURL.appendingPathComponent("\(UUID().uuidString).m4a")
        for settings in Self.settingsOptions {
            guard let recorder = try? AVAudioRecorder(url: url, settings: settings) else { continue }
            recorder.isMeteringEnabled = true
            recorder.delegate = self
            if recorder.prepareToRecord() { return recorder }
            recorder.deleteRecording()
        }
        return nil
    }

    /// Removes header-only files left by prepared recorders that were never
    /// used (the app was closed before the next tap). Bigger files are kept:
    /// they could be the only copy of something.
    func removeUnusedPreparedFiles(keeping queuedFileNames: Set<String>) {
        let inUse = Set([preparedRecorder?.url, currentRecordingURL].compactMap { $0?.lastPathComponent })
        let keys: [URLResourceKey] = [.fileSizeKey]
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: Self.documentsURL,
            includingPropertiesForKeys: keys
        ) else { return }

        for file in files where file.pathExtension == "m4a" {
            let name = file.lastPathComponent
            guard !queuedFileNames.contains(name), !inUse.contains(name) else { continue }
            let size = (try? file.resourceValues(forKeys: Set(keys)).fileSize) ?? Int.max
            if size < Self.emptyFileThreshold {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    // MARK: - Recording

    func startRecording() throws -> URL {
        let session = AVAudioSession.sharedInstance()
        try configureCategoryIfNeeded()
        try session.setActive(true)

        var recorder = preparedRecorder ?? makePreparedRecorder()
        preparedRecorder = nil
        if recorder?.record(forDuration: Self.maxDuration) != true {
            // The prepared one can go stale (route change, session reset).
            // Build a fresh one once before giving up.
            recorder?.deleteRecording()
            recorder = makePreparedRecorder()
            guard let fresh = recorder, fresh.record(forDuration: Self.maxDuration) else {
                recorder?.deleteRecording()
                try? session.setActive(false, options: .notifyOthersOnDeactivation)
                throw WatchAudioRecorderError.couldNotStart
            }
        }
        guard let recorder else { throw WatchAudioRecorderError.couldNotStart }

        audioRecorder = recorder
        currentRecordingURL = recorder.url
        recordingStartTime = Date()
        isRecording = true
        currentDuration = 0

        startTimer()

        return recorder.url
    }

    func stopRecording() -> (url: URL, duration: TimeInterval)? {
        timer?.invalidate()
        timer = nil

        // Measure from the clock, not the last timer tick, so the saved
        // duration doesn't trail by up to 0.1s.
        let duration = recordingStartTime.map { Date().timeIntervalSince($0) } ?? currentDuration
        let url = currentRecordingURL

        audioRecorder?.stop()
        audioRecorder = nil
        isRecording = false
        currentDuration = 0
        audioLevel = 0
        recordingStartTime = nil
        currentRecordingURL = nil

        // Deactivate session so other audio can resume
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )

        guard let recordingURL = url else { return nil }
        return (url: recordingURL, duration: duration)
    }

    /// `recorder` limits it to that recorder, so a late callback from the
    /// last recording can't end the next one.
    private func endedBySystem(recorder: ObjectIdentifier? = nil) {
        guard isRecording, let audioRecorder else { return }
        if let recorder, recorder != ObjectIdentifier(audioRecorder) { return }
        onEndedBySystem?()
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, let startTime = self.recordingStartTime else { return }
                self.currentDuration = Date().timeIntervalSince(startTime)
                self.audioRecorder?.updateMeters()
                let dB = self.audioRecorder?.averagePower(forChannel: 0) ?? -160
                self.audioLevel = Self.normalizeAudioLevel(dB)
            }
        }
    }

    private static func normalizeAudioLevel(_ dB: Float) -> Float {
        max(0, min(1, (dB + 50) / 50))
    }
}

extension WatchAudioRecorderService: AVAudioRecorderDelegate {
    /// Fires after our own stop() too; by then isRecording is false and this
    /// does nothing. If it fires mid-recording, the system ended it.
    nonisolated func audioRecorderDidFinishRecording(
        _ recorder: AVAudioRecorder,
        successfully flag: Bool
    ) {
        let id = ObjectIdentifier(recorder)
        Task { @MainActor in
            self.endedBySystem(recorder: id)
        }
    }

    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        print("Watch recording encode error: \(String(describing: error))")
        let id = ObjectIdentifier(recorder)
        Task { @MainActor in
            self.endedBySystem(recorder: id)
        }
    }
}
