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
    let onPermissionGranted: () -> Void

    @State private var permissionState: MicPermissionState = Self.currentPermissionState()
    @State private var isRequesting = false
    @State private var hasAdvanced = false
    @State private var showPrivacyInfo = false

    var body: some View {
        OnboardingPage {
            VStack(spacing: 0) {
                Spacer().frame(height: 8)

                OnboardingIllustration(name: "illustration-record")
                    .onboardingAppear(delay: 0.05)

                Spacer().frame(height: 18)

                VStack(spacing: 12) {
                    OnboardingHeadline(size: 34) {
                        Text("First, ") + Text("let it hear you.").italic()
                    }

                    OnboardingBody(text: "Ramble records from your iPhone or Apple Watch. Audio stays on your device unless you choose to send it.")
                }
                .padding(.horizontal, 24)
                .onboardingAppear(delay: 0.2)

                Spacer().frame(height: 28)

                permissionRow
                    .padding(.horizontal, 16)
                    .onboardingAppear(delay: 0.35)

                Spacer(minLength: 24)
            }
        } bottomBar: {
            ctaSection
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
                .onboardingAppear(delay: 0.45)
        }
        .onAppear {
            refreshPermissionState()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: UIApplication.willEnterForegroundNotification
            )
        ) { _ in
            refreshPermissionState()
        }
        .sheet(isPresented: $showPrivacyInfo) {
            PrivacyInfoSheet()
        }
    }

    // MARK: - Permission row card

    private var permissionRow: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.obRed)
                    .frame(width: 32, height: 32)

                Image(systemName: "mic.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text("Microphone")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.obInk)

                HStack(spacing: 0) {
                    OnboardingItalicTag(text: tagLabel)
                    Text(" · \(tagSuffix)")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.obInkFaint)
                }
            }

            Spacer()
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.obSurface)
        )
    }

    private var tagLabel: String {
        switch permissionState {
        case .undetermined: return "Required"
        case .granted: return "Enabled"
        case .denied: return "Blocked"
        }
    }

    private var tagSuffix: String {
        switch permissionState {
        case .undetermined: return "only used while recording"
        case .granted: return "ready to record"
        case .denied: return "enable in Settings to continue"
        }
    }

    // MARK: - CTA

    @ViewBuilder
    private var ctaSection: some View {
        VStack(spacing: 0) {
            switch permissionState {
            case .undetermined:
                OnboardingPrimaryButton(
                    title: isRequesting ? "Requesting…" : "Enable Microphone",
                    isDisabled: isRequesting
                ) {
                    requestPermission()
                }
                OnboardingSecondaryLink(title: "How privacy works") {
                    showPrivacyInfo = true
                }
            case .granted:
                OnboardingPrimaryButton(title: "Continue") {
                    advance()
                }
                OnboardingSecondaryLink(title: "How privacy works") {
                    showPrivacyInfo = true
                }
            case .denied:
                OnboardingPrimaryButton(title: "Open Settings") {
                    openAppSettings()
                }
                OnboardingSecondaryLink(title: "How privacy works") {
                    showPrivacyInfo = true
                }
            }
        }
    }

    // MARK: - Permission handling

    private func refreshPermissionState() {
        permissionState = Self.currentPermissionState()
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
                    advance()
                } else {
                    permissionState = .denied
                    HapticService.warning()
                }
            }
        }
    }

    private func advance() {
        guard !hasAdvanced else { return }
        hasAdvanced = true
        onPermissionGranted()
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

#Preview {
    OnboardingView()
}
