//
//  HapticService.swift
//  Ramble
//

import UIKit

enum HapticService {
    // Pre-allocated generators for instant haptics
    private static let heavyGenerator = UIImpactFeedbackGenerator(style: .heavy)
    private static let lightGenerator = UIImpactFeedbackGenerator(style: .light)
    private static let notificationGenerator = UINotificationFeedbackGenerator()

    /// Call once at app launch to wake the Taptic Engine
    static func prepare() {
        heavyGenerator.prepare()
        lightGenerator.prepare()
        notificationGenerator.prepare()
    }

    static func recordStart() {
        heavyGenerator.impactOccurred()
        heavyGenerator.prepare()
    }

    static func recordStop() {
        notificationGenerator.notificationOccurred(.success)
        notificationGenerator.prepare()
    }

    static func buttonTap() {
        lightGenerator.impactOccurred()
        lightGenerator.prepare()
    }
}
