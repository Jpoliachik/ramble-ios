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

    static func buttonTap() {
        WKInterfaceDevice.current().play(.click)
    }
}
