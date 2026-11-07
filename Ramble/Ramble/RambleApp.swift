//
//  RambleApp.swift
//  Ramble
//
//  Created by Justin Poliachik on 1/21/26.
//

import SwiftUI

@main
struct RambleApp: App {
    @AppStorage("appearanceMode") private var appearanceMode: String = AppearanceMode.system.rawValue
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false
    @AppStorage(Consent.key) private var hasConsented: Bool = false

    init() {
        BackgroundTaskService.shared.registerBackgroundTasks()
        Self.migrateKeychainIfUnlocked()
        // Registered here, not on a view, so it also fires when Ramble is
        // running in the background (no scene) and the phone unlocks. Work
        // that waited for the Keychain picks up from here.
        NotificationCenter.default.addObserver(
            forName: UIApplication.protectedDataDidBecomeAvailableNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                Self.migrateKeychainIfUnlocked()
                BackgroundTaskService.shared.beginImmediateBackgroundProcessing()
            }
        }
        _ = PhoneConnectivityService.shared
        DeliveryMonitor.shared.start()
        HapticService.prepare()

        Task { @MainActor in
            await PurchaseService.shared.start()
        }
    }

    var body: some Scene {
        WindowGroup {
            MainView()
                // Onboarding done in an earlier build, without the consent
                // line: ask once before anything uploads (specs/phone.md).
                .sheet(isPresented: Binding(
                    get: { hasCompletedOnboarding && !hasConsented },
                    set: { _ in }
                )) {
                    ConsentNoticeView()
                        .interactiveDismissDisabled()
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
                .purchaseNotices()
                .onReceive(
                    NotificationCenter.default.publisher(
                        for: UIApplication.didEnterBackgroundNotification
                    )
                ) { _ in
                    NoteSyncService.shared.stopForegroundPolling()
                    // ~30s to finish uploads and the check-in.
                    BackgroundTaskService.shared.beginImmediateBackgroundProcessing()
                    BackgroundTaskService.shared.scheduleSyncTask()
                    BackgroundTaskService.shared.scheduleRefreshTask()
                    // Hand any stuck-note alerts to the system now, in case
                    // Ramble doesn't run again for a while.
                    DeliveryMonitor.shared.evaluate()
                }
                .onReceive(
                    NotificationCenter.default.publisher(
                        for: UIApplication.didBecomeActiveNotification
                    )
                ) { _ in
                    // Also covers a cold launch: upload, then check in.
                    BackgroundTaskService.shared.appDidOpen()
                    NoteSyncService.shared.startForegroundPolling()
                    DeliveryMonitor.shared.evaluateSoon()
                }
        }
    }

    /// Keychain items can only be migrated while the phone is unlocked.
    private static func migrateKeychainIfUnlocked() {
        guard UIApplication.shared.isProtectedDataAvailable else { return }
        KeychainService.migrateAccessibilityIfNeeded()
    }
}
