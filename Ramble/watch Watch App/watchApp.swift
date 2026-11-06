//
//  watchApp.swift
//  watch Watch App
//
//  Created by Justin Poliachik on 1/21/26.
//

import SwiftUI

@main
struct watch_Watch_AppApp: App {
    // Initialize shared services on launch so persistent state is loaded,
    // WatchConnectivity is activated and the background upload session is
    // reconnected as early as possible.
    private let store = WatchNoteStore.shared
    private let connectivity = WatchConnectivityService.shared
    private let relay = WatchRelayService.shared

    var body: some Scene {
        WindowGroup {
            WatchMainView()
        }
        // Receipts, the application context (a new token) and the unlock
        // can arrive while Ramble is asleep. Wake to read them, so held notes
        // upload and the audio the phone has is freed.
        .backgroundTask(.watchConnectivity) {
            await WatchConnectivityService.shared.waitForPendingContent()
        }
        // Results of note uploads that finished while the app was suspended.
        .backgroundTask(.urlSession(RelayUploadSession.identifier)) {
            await RelayUploadSession.shared.waitForEvents()
        }
        // Best-effort passes while the app is closed: retry waiting notes,
        // read transcripts, retry fair-use holds after the reset.
        .backgroundTask(.appRefresh(WatchRelayService.backgroundRefreshTaskID)) {
            await WatchRelayService.shared.backgroundPass()
        }
    }
}
