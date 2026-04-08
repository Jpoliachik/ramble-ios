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
    }
}
