//
//  ThisDevice.swift
//  Ramble
//
//  iPhone or iPad, for copy and the few places an iPad differs: an Apple
//  Watch pairs only with an iPhone, so an iPad never shows watch setup.
//  Read from the hardware model so it works from any isolation domain.
//

import Foundation

enum ThisDevice {
    nonisolated static let isPad: Bool = {
        if let model = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return model.hasPrefix("iPad")
        }
        var size = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        var machine = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.machine", &machine, &size, nil, 0)
        return String(cString: machine).hasPrefix("iPad")
    }()

    /// "iPad" or "iPhone".
    nonisolated static var name: String { isPad ? "iPad" : "iPhone" }
}
