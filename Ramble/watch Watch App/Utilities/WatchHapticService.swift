//
//  WatchHapticService.swift
//  watch Watch App
//

import WatchKit

enum WatchHapticService {
    static func recordStart() {
        WKInterfaceDevice.current().play(.start)
    }

    static func recordStop() {
        WKInterfaceDevice.current().play(.success)
    }

    static func failure() {
        WKInterfaceDevice.current().play(.failure)
    }

    /// Five minutes left before the 60-minute cap.
    static func capWarning() {
        WKInterfaceDevice.current().play(.notification)
    }
}
