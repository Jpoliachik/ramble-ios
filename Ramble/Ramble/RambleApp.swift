//
//  RambleApp.swift
//  Ramble
//
//  Created by Justin Poliachik on 1/21/26.
//

import SwiftUI

@main
struct RambleApp: App {
    @Environment(\.scenePhase) private var scenePhase
    /// Set when a widget, control or Live Activity asks for a recording. Acted on
    /// once the scene is active: AVAudioSession activation fails while the app is
    /// still inactive, which is exactly the state a URL launch arrives in.
    @State private var recordRequested = false
    @AppStorage("appearanceMode") private var appearanceMode: String = AppearanceMode.system.rawValue
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false

    init() {
        // Before anything reads settings: brings keychain items written by older
        // builds up to an accessibility background work can actually read.
        SettingsService.shared.migrateKeychainAccessibilityIfNeeded()

        BackgroundTaskService.shared.registerBackgroundTasks()
        _ = PhoneConnectivityService.shared
        HapticService.prepare()

        // Proactively download the speech model so transcription works immediately
        Task {
            await TranscriptionQueueService.shared.prepareModelIfNeeded()
        }

        // A Whisper download interrupted by app termination picks up here
        LocalWhisperTranscriptionService.shared.resumeDownloadIfNeeded()

        // A crash mid-recording leaves a Live Activity ticking with nothing behind it
        LiveActivityService.shared.endOrphanedActivities()

        // Initialize subscription service and fetch products
        Task {
            await SubscriptionService.shared.start()
        }
    }

    /// Toggling means a second tap from the same surface stops the recording
    /// rather than starting a second one.
    private func performRecordRequest() {
        guard recordRequested else { return }
        recordRequested = false
        Task {
            let manager = RecordingManager.shared
            if manager.isRecording {
                manager.stopRecording()
            } else {
                await manager.startRecording()
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            MainView()
                // ramble://record arrives from the home screen widget, the Control
                // Center button and the Live Activity. Toggling means a second tap
                // stops the recording rather than starting a second one.
                .onOpenURL { url in
                    guard url.host == "record" else { return }
                    recordRequested = true
                    if scenePhase == .active { performRecordRequest() }
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { performRecordRequest() }
                }
                .preferredColorScheme(
                    AppearanceMode(rawValue: appearanceMode)?.colorScheme
                )
                .sheet(isPresented: Binding(
                    get: { !hasCompletedOnboarding },
                    set: { isPresented in
                        if !isPresented { hasCompletedOnboarding = true }
                    }
                )) {
                    OnboardingView()
                        .interactiveDismissDisabled()
                }
                .onReceive(
                    NotificationCenter.default.publisher(
                        for: UIApplication.didEnterBackgroundNotification
                    )
                ) { _ in
                    // Immediate ~30s background time for in-flight transcription + webhook
                    BackgroundTaskService.shared.beginImmediateBackgroundProcessing()
                    // Also schedule deferred BGProcessingTask as fallback
                    BackgroundTaskService.shared.scheduleSyncTask()
                }
                .onReceive(
                    NotificationCenter.default.publisher(
                        for: UIApplication.willEnterForegroundNotification
                    )
                ) { _ in
                    TranscriptionQueueService.shared.resumePendingJobs()
                    WebhookQueueService.shared.resumePendingJobs()
                    LocalWhisperTranscriptionService.shared.resumeDownloadIfNeeded()
                    // Held for the whole session; this only matters if iOS reclaimed
                    // the weights while the app sat in the background.
                    LocalWhisperTranscriptionService.shared.keepModelWarm()
                }
        }
    }
}
