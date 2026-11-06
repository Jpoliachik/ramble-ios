//
//  watchApp.swift
//  watch Watch App
//
//  Created by Justin Poliachik on 1/21/26.
//

import SwiftUI

@main
struct watch_Watch_AppApp: App {
    // Initialize shared services on launch so persistent state is loaded early
    private let syncQueue = WatchSyncQueue.shared
    private let connectivity = WatchConnectivityService.shared

    var body: some Scene {
        WindowGroup {
            WatchMainView()
        }
        // The phone's "saved it" receipts can arrive while Ramble is asleep.
        // Wake to read them, so the watch frees the audio and doesn't alert
        // about notes the phone already has.
        .backgroundTask(.watchConnectivity) {
            await WatchConnectivityService.shared.waitForPendingContent()
        }
        // Retries notes still waiting for the phone while the app is
        // suspended, when its own retry timer can't fire.
        .backgroundTask(.appRefresh(WatchConnectivityService.backgroundRetryTaskID)) {
            await WatchConnectivityService.shared.runBackgroundRetry()
        }
    }
}
