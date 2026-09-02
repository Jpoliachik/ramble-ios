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


    /// Toggling rather than starting means a second tap ends the recording.
    private func toggleRecording() {
        let manager = WatchRecordingManager.shared
        if manager.isRecording {
            manager.stopRecordingAndTransfer()
        } else {
            manager.startRecording()
        }
    }

    var body: some Scene {
        WindowGroup {
            WatchMainView()
                // The complication and the Control Center button raise a flag and
                // open the app; this is where the recording actually starts, because
                // only a foreground app may take the microphone.
                .onOpenURL { url in
                    guard url.host == "record" else { return }
                    toggleRecording()
                }
        }
    }
}
