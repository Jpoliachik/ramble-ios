//
//  WatchMainView.swift
//  watch Watch App
//
//  One button in the center, one bar at the bottom. The button is the only
//  way to start and stop. The bar holds a short alert on the left, the
//  timer in the middle while recording, and history on the right. Status
//  is shown with icons and motion; the words live one tap away.
//

import AVFoundation
import SwiftUI
import WatchKit

struct WatchMainView: View {
    @StateObject private var recordingManager = WatchRecordingManager.shared
    @StateObject private var connectivity = WatchConnectivityService.shared
    @StateObject private var syncQueue = WatchSyncQueue.shared
    @StateObject private var history = WatchRecordingHistory.shared

    @Environment(\.scenePhase) private var scenePhase

    /// Ignores extra taps while the mic permission prompt or session setup is pending.
    @State private var isStarting = false
    @State private var micDenied = false
    /// Set for 3 s after a start fails for a reason other than permission.
    @State private var micBusyToken: UUID?
    @State private var showCheck = false
    @State private var checkToken = UUID()
    /// Bumped to shake the alert when a tap can't record.
    @State private var nudge = 0
    @State private var path: [WatchRoute] = []
    @State private var now = Date()

    /// 58% of the screen width: 120pt on a 46mm watch.
    private let buttonSize = (WKInterfaceDevice.current().screenBounds.width * 0.58).rounded()

    private var isRecording: Bool { recordingManager.isRecording }

    private var alert: WatchAlert? {
        WatchAlert.resolve(
            micDenied: micDenied,
            micBusy: micBusyToken != nil,
            companionAppInstalled: connectivity.isCompanionAppInstalled,
            phoneNeedsUnlock: connectivity.phoneNeedsUnlock
        )
    }

    var body: some View {
        // The observed services re-render this view whenever the queue, the
        // session or the history changes. `now` moves on each foreground, so
        // a note that crossed the stuck threshold turns red.
        let notes = WatchDelivery.notes(now: now)
        let badge = WatchHistoryBadge.resolve(
            notes,
            seenLostIDs: history.seenLostIDs
        )

        NavigationStack(path: $path) {
            WatchRecordButtonView(
                size: buttonSize,
                isRecording: isRecording,
                audioLevel: recordingManager.audioLevel,
                showCheck: showCheck,
                breathe: history.entries.isEmpty && !micDenied,
                dimmed: micDenied
            ) {
                Task { await toggleRecording() }
            }
            // Centered on the whole screen, not the safe area, so it never
            // moves when the bar changes.
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()
            .toolbar {
                ToolbarItemGroup(placement: .bottomBar) {
                    alertItem
                    Spacer()
                    if isRecording {
                        timer
                        Spacer()
                    }
                    if !isRecording {
                        WatchHistoryButton(badge: badge) {
                            path.append(.recent)
                        }
                        .transition(.opacity)
                    }
                }
            }
            .animation(.easeInOut(duration: 0.2), value: isRecording)
            .animation(.easeOut(duration: 0.25), value: alert)
            .navigationDestination(for: WatchRoute.self) { route in
                switch route {
                case .recent: WatchRecordingsListView()
                case .alert(let alert): WatchAlertDetailView(alert: alert)
                }
            }
        }
        .onAppear {
            refreshOnForeground()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                refreshOnForeground()
            }
        }
        .onChange(of: recordingManager.stopCount) { _, _ in
            flashCheck()
        }
    }

    // MARK: - Bar

    @ViewBuilder
    private var alertItem: some View {
        if let alert {
            if isRecording {
                // Words drop while recording; the timer gets the middle
                Image(systemName: alert.symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(alert.isBlocking ? Color.red : Color.secondary)
                    .accessibilityLabel(alert.detailTitle)
            } else {
                WatchAlertLabel(alert: alert, nudge: nudge) {
                    if alert.hasDetail { path.append(.alert(alert)) }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private var timer: some View {
        Text(WatchFormat.duration(recordingManager.currentDuration))
            .font(.system(size: 26, weight: .bold, design: .serif))
            .monospacedDigit()
            .foregroundStyle(Color.brandAmber)
            .contentTransition(.numericText())
            .accessibilityLabel("Recording, \(WatchFormat.spokenDuration(recordingManager.currentDuration))")
    }

    // MARK: - Actions

    private func refreshOnForeground() {
        micDenied = AVAudioApplication.shared.recordPermission == .denied
        now = Date()
        // Queued behind the first frame. Getting the recorder ready comes
        // first, since a tap can follow the launch almost at once.
        Task { @MainActor in
            recordingManager.prewarm()
            // Retry anything still waiting, including transfers from previous sessions
            syncQueue.pruneOrphanedJobs()
            connectivity.retryPendingTransfers()
            recordingManager.removeUnusedPreparedFiles()
            WatchStuckNoteAlerts.shared.update()
        }
    }

    /// A tap always records on the watch, whatever the phone is doing.
    private func toggleRecording() async {
        if recordingManager.isRecording {
            WatchHapticService.recordStop()
            recordingManager.stopRecordingAndTransfer()
            return
        }
        guard !isStarting else { return }
        if micDenied {
            WatchHapticService.failure()
            nudge += 1
            return
        }
        isStarting = true
        defer { isStarting = false }
        showCheck = false
        micBusyToken = nil
        if await recordingManager.startRecording() {
            WatchHapticService.recordStart()
        } else {
            WatchHapticService.failure()
            if recordingManager.isMicrophoneDenied {
                micDenied = true
            } else {
                await showMicBusy()
            }
        }
    }

    private func flashCheck() {
        let token = UUID()
        checkToken = token
        showCheck = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(800))
            if checkToken == token { showCheck = false }
        }
    }

    private func showMicBusy() async {
        let token = UUID()
        micBusyToken = token
        try? await Task.sleep(for: .seconds(3))
        if micBusyToken == token { micBusyToken = nil }
    }
}

enum WatchRoute: Hashable {
    case recent
    case alert(WatchAlert)
}

// MARK: - Bar pieces

/// Icon plus two or three words. Red when it stops a recording.
private struct WatchAlertLabel: View {
    let alert: WatchAlert
    let nudge: Int
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Read once here: the keyframe closure is Sendable and can't touch the environment
        let shakes = !reduceMotion
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: alert.symbol)
                Text(alert.shortText)
                    .lineLimit(1)
                    .fixedSize()
                if alert.hasDetail {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.tertiary)
                }
            }
            .font(.system(size: 13.5, weight: .semibold))
            .foregroundStyle(alert.isBlocking ? Color.red : Color.secondary)
        }
        .buttonStyle(.plain)
        .keyframeAnimator(initialValue: CGFloat(0), trigger: nudge) { content, offset in
            content.offset(x: shakes ? offset : 0)
        } keyframes: { _ in
            KeyframeTrack {
                LinearKeyframe(-5, duration: 0.06)
                LinearKeyframe(5, duration: 0.06)
                LinearKeyframe(-3, duration: 0.06)
                LinearKeyframe(3, duration: 0.06)
                LinearKeyframe(0, duration: 0.06)
            }
        }
        .accessibilityLabel(alert.detailTitle)
        .accessibilityHint(alert.hasDetail ? "Double tap for help" : "")
    }
}

/// Opens Recent. Its badge is the only delivery status on the home screen.
struct WatchHistoryButton: View {
    let badge: WatchHistoryBadge
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            Image(systemName: "list.bullet")
        }
        .overlay {
            if badge == .moving && !reduceMotion {
                SpinningRing()
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .topTrailing) {
            if let color = dotColor {
                Circle()
                    .fill(color)
                    .frame(width: 12, height: 12)
                    .overlay(Circle().stroke(Color.black, lineWidth: 2))
                    .offset(x: 2, y: -2)
                    .transition(.scale.combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.5), value: badge)
        .accessibilityLabel("Recent")
        .accessibilityValue(accessibilityValue)
    }

    private var dotColor: Color? {
        switch badge {
        case .needsYou: return .red
        case .waiting: return Color.white.opacity(0.7)
        // With Reduce Motion the ring doesn't spin, so a gray dot stands in
        case .moving: return reduceMotion ? Color.white.opacity(0.7) : nil
        case .none: return nil
        }
    }

    private var accessibilityValue: String {
        switch badge {
        case .needsYou: return "A note needs you"
        case .moving: return "Sending to iPhone"
        case .waiting: return "Notes waiting for iPhone"
        case .none: return ""
        }
    }
}

private struct SpinningRing: View {
    @State private var angle: Double = 0

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.3)
            .stroke(Color.white.opacity(0.9), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            .padding(-4)
            .rotationEffect(.degrees(angle))
            .onAppear {
                withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                    angle = 360
                }
            }
            .accessibilityHidden(true)
    }
}

#Preview {
    WatchMainView()
}
