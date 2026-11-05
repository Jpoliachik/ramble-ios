//
//  OnboardingWatchStep.swift
//  Ramble
//
//  Get Ramble onto the watch. Reads WCSession's paired / installed flags
//  (a local check, no network) and shows one of three states:
//  - not installed: a picture of the Watch app's Available Apps row with
//    Ramble's icon, plus a button that opens the Watch app. Continue stays
//    disabled until the install lands, then this flips by itself.
//  - installed: the round app icon on a watch face, so people know what to
//    look for.
//  - no paired watch: you can record on iPhone too.
//

import SwiftUI
import WatchConnectivity

struct OnboardingWatchStep: View {
    let onFinish: () -> Void

    @Environment(\.openURL) private var openURL
    @State private var state: WatchInstallState = .checking
    @State private var checks = 0
    /// The Watch app link is undocumented; hide the button if it won't open.
    @State private var openFailed = false

    var body: some View {
        Group {
            switch state {
            case .checking:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .notInstalled:
                notInstalled
            case .installed:
                installed
            case .noWatch:
                noWatch
            }
        }
        .animation(.smooth(duration: 0.35), value: state)
        .task {
            // Re-read the flags every couple of seconds while this screen is
            // up, so it flips as soon as the install finishes.
            while !Task.isCancelled {
                refresh()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func refresh() {
        checks += 1
        var next = WatchInstallState.current()
        // WCSession can take a moment to activate. Don't spin forever.
        if next == .checking && checks > 2 { next = .notInstalled }
        guard next != state else { return }
        if next == .installed && state == .notInstalled { HapticService.success() }
        state = next
    }

    // MARK: - Not installed

    private var notInstalled: some View {
        OnboardingPage {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    OnboardingHeadline(size: 34, alignment: .leading) {
                        Text("Now, put it ") + Text("on your watch.").italic().foregroundColor(Color.obInkSoft)
                    }
                    OnboardingBody(text: "In the Watch app, find Ramble and tap Install.", maxWidth: nil, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 12)

                VStack(spacing: 10) {
                    AvailableAppsPicture()
                    if !openFailed {
                        openWatchRow
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 24)

                Spacer(minLength: 24)
            }
        } bottomBar: {
            VStack(spacing: 0) {
                OnboardingPrimaryButton(title: "Continue", isDisabled: true, action: onFinish)
                HStack(spacing: 0) {
                    OnboardingSecondaryLink(title: "No Apple Watch?", action: onFinish)
                    OnboardingSecondaryLink(title: "Later", action: onFinish)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
    }

    private var openWatchRow: some View {
        Button {
            HapticService.buttonTap()
            guard let url = URL(string: "itms-watchs://") else { return }
            openURL(url) { accepted in
                if !accepted { openFailed = true }
            }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "applewatch")
                    .font(.system(size: 24, weight: .regular))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(Color.black, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Open the Watch app")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.obInk)
                    Text("Then scroll down to Available Apps")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.obInkFaint)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.obInkFaint)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Installed

    private var installed: some View {
        OnboardingPage {
            VStack(spacing: 22) {
                Spacer(minLength: 40)

                OnboardingWatchFrame {
                    Image("ramble-app-icon")
                        .resizable()
                        .scaledToFill()
                        .frame(width: 66, height: 66)
                        .clipShape(Circle())
                }
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.onOnboardingAmber)
                        .frame(width: 32, height: 32)
                        .background(Color.brandAmber, in: Circle())
                        .offset(x: 14, y: -10)
                        .transition(.scale.combined(with: .opacity))
                }
                .scaleEffect(1.25)
                .padding(.bottom, 24)

                OnboardingHeadline(size: 32) {
                    Text("Ramble is ") + Text("on your watch.").italic().foregroundColor(Color.brandAmber)
                }
                OnboardingBody(text: "Look for this icon on your watch and tap it to open Ramble.")

                Spacer(minLength: 24)
            }
            .padding(.horizontal, 24)
        } bottomBar: {
            OnboardingPrimaryButton(title: "Continue", action: onFinish)
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
        }
    }

    // MARK: - No watch

    private var noWatch: some View {
        OnboardingPage {
            VStack(spacing: 22) {
                Spacer(minLength: 40)

                ZStack {
                    Circle().stroke(Color.brandAmber, lineWidth: 5).frame(width: 84, height: 84)
                    Circle().fill(Color.brandAmber).frame(width: 64, height: 64)
                }
                .accessibilityHidden(true)

                OnboardingHeadline(size: 32) {
                    Text("No watch? ") + Text("No problem.").italic().foregroundColor(Color.obInkSoft)
                }
                OnboardingBody(text: "Ramble works best on Apple Watch, but you can record right here on your iPhone too.")

                Spacer(minLength: 24)
            }
            .padding(.horizontal, 24)
        } bottomBar: {
            OnboardingPrimaryButton(title: "Continue", action: onFinish)
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
        }
    }
}

// MARK: - Install state

enum WatchInstallState: Equatable {
    case checking, notInstalled, installed, noWatch

    static func current() -> WatchInstallState {
        guard WCSession.isSupported() else { return .noWatch }
        let session = WCSession.default
        guard session.activationState == .activated else { return .checking }
        guard session.isPaired else { return .noWatch }
        return session.isWatchAppInstalled ? .installed : .notInstalled
    }
}

// MARK: - Available Apps picture

/// A drawing of the Watch app's "Available Apps" list with just Ramble's row,
/// so people know what to look for after they switch apps.
private struct AvailableAppsPicture: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("AVAILABLE APPS")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.obInkFaint)
                .padding(.horizontal, 16)

            HStack(spacing: 12) {
                Image("ramble-app-icon")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 38, height: 38)
                    .clipShape(Circle())
                Text("Ramble")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.obInk)
                Spacer()
                Text("INSTALL")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 5)
                    .background(Color.blue, in: Capsule())
                    .background {
                        if !reduceMotion {
                            Capsule()
                                .stroke(Color.blue, lineWidth: 2)
                                .phaseAnimator([false, true]) { ring, expanded in
                                    ring
                                        .scaleEffect(expanded ? 1.25 : 1)
                                        .opacity(expanded ? 0 : 0.5)
                                } animation: { expanded in
                                    expanded ? .easeOut(duration: 1.6) : .linear(duration: 0)
                                }
                        }
                    }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.brandAmberSoft)
        }
        .padding(.top, 12)
        .padding(.bottom, 4)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("In the Watch app's Available Apps list, tap Install next to Ramble.")
    }
}

#Preview {
    OnboardingWatchStep(onFinish: {})
        .background(Color(.systemGroupedBackground))
}
