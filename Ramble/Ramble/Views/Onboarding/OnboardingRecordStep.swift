//
//  OnboardingRecordStep.swift
//  Ramble
//

import AVFoundation
import SwiftUI
import UIKit

enum MicPermissionState {
    case undetermined
    case granted
    case denied
}

struct OnboardingRecordStep: View {
    let namespace: Namespace.ID
    let onPermissionGranted: () -> Void

    @State private var permissionState: MicPermissionState = Self.currentPermissionState()
    @State private var isRequesting = false
    @State private var buttonShake: CGFloat = 0
    @State private var iconsAppeared = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 16)

            // Paired mic + watch sketches
            HStack(spacing: 24) {
                MicSketchIcon(active: permissionState == .granted)
                    .opacity(iconsAppeared ? 1 : 0)
                    .scaleEffect(iconsAppeared ? 1 : 0.6)

                Image(systemName: "applewatch.radiowaves.left.and.right")
                    .font(.system(size: 44, weight: .regular))
                    .foregroundStyle(.secondary)
                    .opacity(iconsAppeared ? 0.85 : 0)
                    .scaleEffect(iconsAppeared ? 1 : 0.6)
            }
            .frame(height: 96)

            Spacer().frame(height: 24)

            OnboardingStepHeader(
                eyebrow: "Step 1 · Record",
                title: "Just talk",
                subtitle: "Ramble captures your voice notes so you don't have to think. Best on the go — phone in your pocket, or straight from your Apple Watch."
            )

            Spacer()

            ctaSection
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
                .onboardingAppear(delay: 0.4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.65).delay(0.15)) {
                iconsAppeared = true
            }
            refreshPermissionState()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: UIApplication.willEnterForegroundNotification
            )
        ) { _ in
            refreshPermissionState()
        }
    }

    @ViewBuilder
    private var ctaSection: some View {
        switch permissionState {
        case .undetermined:
            OnboardingPrimaryButton(title: isRequesting ? "Requesting…" : "Enable Microphone", isDisabled: isRequesting) {
                requestPermission()
            }
            .offset(x: buttonShake)
        case .denied:
            VStack(spacing: 10) {
                OnboardingPrimaryButton(title: "Open Settings") {
                    openAppSettings()
                }
                Text("Ramble needs microphone access to record. Enable it in Settings to continue.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
            }
        case .granted:
            // Transient success state before auto-advance.
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.title3)
                Text("Microphone ready")
                    .font(.headline)
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
        }
    }

    // MARK: - Permission handling

    private func refreshPermissionState() {
        let previous = permissionState
        let new = Self.currentPermissionState()
        permissionState = new
        if new == .granted && previous != .granted {
            advanceAfterGrant()
        }
    }

    private static func currentPermissionState() -> MicPermissionState {
        switch AVAudioSession.sharedInstance().recordPermission {
        case .undetermined: return .undetermined
        case .denied: return .denied
        case .granted: return .granted
        @unknown default: return .undetermined
        }
    }

    private func requestPermission() {
        isRequesting = true
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            DispatchQueue.main.async {
                isRequesting = false
                if granted {
                    permissionState = .granted
                    HapticService.success()
                    advanceAfterGrant()
                } else {
                    permissionState = .denied
                    HapticService.warning()
                    triggerShake()
                }
            }
        }
    }

    private func advanceAfterGrant() {
        Task {
            try? await Task.sleep(nanoseconds: 650_000_000)
            await MainActor.run { onPermissionGranted() }
        }
    }

    private func triggerShake() {
        let values: [CGFloat] = [-10, 10, -8, 8, -4, 4, 0]
        for (i, v) in values.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.05) {
                withAnimation(.easeInOut(duration: 0.05)) {
                    buttonShake = v
                }
            }
        }
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

/// Hand-drawn-ish microphone icon that gains a red rim glow when active.
private struct MicSketchIcon: View {
    let active: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.red.opacity(active ? 0.18 : 0.0))
                .frame(width: 72, height: 72)
                .blur(radius: active ? 8 : 0)

            Image(systemName: "mic.fill")
                .font(.system(size: 44, weight: .regular))
                .foregroundStyle(active ? Color.red : Color.primary)
                .symbolEffect(.pulse, options: active ? .repeating : .nonRepeating)
        }
        .animation(.easeInOut(duration: 0.4), value: active)
    }
}

#Preview {
    OnboardingView()
}
