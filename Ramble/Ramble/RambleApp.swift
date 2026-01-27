//
//  RambleApp.swift
//  Ramble
//
//  Created by Justin Poliachik on 1/21/26.
//

import SwiftUI

@main
struct RambleApp: App {
    init() {
        BackgroundTaskService.shared.registerBackgroundTasks()
        _ = PhoneConnectivityService.shared
        HapticService.prepare()
    }

    var body: some Scene {
        WindowGroup {
            MainView()
                .onReceive(
                    NotificationCenter.default.publisher(
                        for: UIApplication.didEnterBackgroundNotification
                    )
                ) { _ in
                    BackgroundTaskService.shared.scheduleTranscriptionTask()
                }
        }
    }
}
