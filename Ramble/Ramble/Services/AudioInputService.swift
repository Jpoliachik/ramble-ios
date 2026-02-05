//
//  AudioInputService.swift
//  Ramble
//
//  Manages audio input device selection and monitoring
//

import AVFoundation
import Combine
import Foundation

/// Represents an available audio input device
struct AudioInput: Identifiable, Equatable {
    let id: String
    let name: String
    let portType: AVAudioSession.Port
    let port: AVAudioSessionPortDescription

    /// User-friendly display name
    var displayName: String {
        // Provide friendlier names for common port types
        switch portType {
        case .bluetoothHFP, .bluetoothA2DP:
            return name // Usually already has device name like "AirPods Pro"
        case .builtInMic:
            return "iPhone Microphone"
        case .headsetMic:
            return "Wired Headset"
        case .usbAudio:
            return "USB Audio"
        default:
            return name
        }
    }

    /// SF Symbol icon for this input type
    var iconName: String {
        switch portType {
        case .bluetoothHFP, .bluetoothA2DP:
            if name.lowercased().contains("airpods") {
                return "airpodspro"
            }
            return "headphones"
        case .builtInMic:
            return "iphone"
        case .headsetMic:
            return "headphones"
        case .usbAudio:
            return "cable.connector"
        default:
            return "mic"
        }
    }

    static func == (lhs: AudioInput, rhs: AudioInput) -> Bool {
        lhs.id == rhs.id
    }
}

@MainActor
final class AudioInputService: ObservableObject {
    static let shared = AudioInputService()

    /// Currently available audio inputs
    @Published private(set) var availableInputs: [AudioInput] = []

    /// The currently active input (from audio route)
    @Published private(set) var currentInput: AudioInput?

    /// User-selected preferred input (persisted)
    @Published var preferredInputId: String? {
        didSet {
            UserDefaults.standard.set(preferredInputId, forKey: "preferredAudioInputId")
        }
    }

    private var routeChangeObserver: NSObjectProtocol?

    private init() {
        // Load saved preference
        preferredInputId = UserDefaults.standard.string(forKey: "preferredAudioInputId")

        // Initial refresh
        refreshAvailableInputs()

        // Monitor for audio route changes (devices connecting/disconnecting)
        routeChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.handleRouteChange(notification)
            }
        }
    }

    deinit {
        if let observer = routeChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    /// Refresh the list of available audio inputs
    func refreshAvailableInputs() {
        let session = AVAudioSession.sharedInstance()

        guard let inputs = session.availableInputs else {
            availableInputs = []
            currentInput = nil
            return
        }

        availableInputs = inputs.map { port in
            AudioInput(
                id: port.uid,
                name: port.portName,
                portType: port.portType,
                port: port
            )
        }

        // Update current input from active route
        if let activeInput = session.currentRoute.inputs.first {
            currentInput = availableInputs.first { $0.id == activeInput.uid }
        } else {
            currentInput = availableInputs.first
        }

        // If preferred input is no longer available, clear it
        if let prefId = preferredInputId,
           !availableInputs.contains(where: { $0.id == prefId }) {
            preferredInputId = nil
        }
    }

    /// Select a specific audio input
    /// - Parameter input: The input to select, or nil to use system default
    /// - Returns: true if successful
    @discardableResult
    func selectInput(_ input: AudioInput?) -> Bool {
        let session = AVAudioSession.sharedInstance()

        do {
            if let input = input {
                try session.setPreferredInput(input.port)
                preferredInputId = input.id
            } else {
                try session.setPreferredInput(nil)
                preferredInputId = nil
            }

            // Refresh to update currentInput
            refreshAvailableInputs()
            return true
        } catch {
            print("Failed to set preferred input: \(error)")
            return false
        }
    }

    /// Apply the user's preferred input if available
    /// Call this before starting a recording
    func applyPreferredInput() {
        refreshAvailableInputs()

        // If user has a preference and it's available, apply it
        if let prefId = preferredInputId,
           let preferredInput = availableInputs.first(where: { $0.id == prefId }) {
            selectInput(preferredInput)
        } else if let bluetoothInput = availableInputs.first(where: {
            $0.portType == .bluetoothHFP || $0.portType == .bluetoothA2DP
        }) {
            // Auto-select Bluetooth/AirPods if available and no explicit preference
            selectInput(bluetoothInput)
        }
    }

    /// Get the preferred input if available, otherwise best available
    var effectiveInput: AudioInput? {
        if let prefId = preferredInputId,
           let preferred = availableInputs.first(where: { $0.id == prefId }) {
            return preferred
        }
        // Prefer Bluetooth over built-in
        if let bluetooth = availableInputs.first(where: {
            $0.portType == .bluetoothHFP || $0.portType == .bluetoothA2DP
        }) {
            return bluetooth
        }
        return availableInputs.first
    }

    private func handleRouteChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }

        switch reason {
        case .newDeviceAvailable, .oldDeviceUnavailable, .override, .categoryChange:
            refreshAvailableInputs()
        default:
            break
        }
    }
}
