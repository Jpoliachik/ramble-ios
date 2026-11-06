//
//  OnboardingIntroStep.swift
//  Ramble
//
//  Three short beats that say what Ramble is: say it to your watch, leave
//  your phone behind, your agent handles it. Each beat has one small loop.
//  A story-style bar fills while a beat plays, then moves on by itself.
//  Swiping works too, and "Get started" is always there.
//

import SwiftUI

struct OnboardingIntroStep: View {
    let onContinue: () -> Void

    @State private var beat = 0
    @State private var fill: CGFloat = 0

    private static let beatDuration: Double = 6

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            IntroSegmentBar(count: IntroBeat.allCases.count, current: beat, fill: fill)
                .padding(.horizontal, 24)
                .padding(.top, 12)

            OnboardingWordmark(size: 20)
                .padding(.horizontal, 24)
                .padding(.top, 18)

            TabView(selection: $beat) {
                ForEach(IntroBeat.allCases) { item in
                    IntroBeatPage(beat: item)
                        .padding(.horizontal, 24)
                        .tag(item.rawValue)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            OnboardingPrimaryButton(title: "Get started", action: onContinue)
                .padding(.horizontal, 16)
                .padding(.top, 12)

            // Tapping "Get started" is the consent (specs/phone.md).
            (Text("Ramble sends your recordings to a cloud service to turn them into text, then sends the text to your agent. ")
                + Text("[Privacy](https://ramble.watch/privacy)").foregroundColor(Color.brandAmber))
                .font(.system(size: 12))
                .foregroundStyle(Color.obInkFaint)
                .tint(Color.brandAmber)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 28)
                .padding(.top, 10)
                .padding(.bottom, 20)
        }
        .task(id: beat) { await playBeat() }
    }

    /// Fills the current segment over `beatDuration`, then advances. Swiping
    /// changes `beat`, which cancels this task and starts the next one.
    private func playBeat() async {
        var reset = Transaction()
        reset.disablesAnimations = true
        withTransaction(reset) { fill = 0 }
        await Task.yield()
        withAnimation(.linear(duration: Self.beatDuration)) { fill = 1 }

        try? await Task.sleep(for: .seconds(Self.beatDuration))
        guard !Task.isCancelled, beat < IntroBeat.allCases.count - 1 else { return }
        withAnimation(.smooth(duration: 0.4)) { beat += 1 }
    }
}

// MARK: - Beats

private enum IntroBeat: Int, CaseIterable, Identifiable {
    case sayIt
    case leavePhone
    case agentHandles

    var id: Int { rawValue }

    var headline: Text {
        switch self {
        case .sayIt:
            return Text("Say it ") + Text("to your watch.").italic().foregroundColor(Color.obInkSoft)
        case .leavePhone:
            return Text("Leave your phone ") + Text("behind.").italic().foregroundColor(Color.obInkSoft)
        case .agentHandles:
            return Text("Your agent ") + Text("handles it.").italic().foregroundColor(Color.obInkSoft)
        }
    }

    var body: String {
        switch self {
        case .sayIt: return "Tap once and talk. That's it."
        case .leavePhone: return "Notes wait on your watch and catch up later."
        case .agentHandles: return "Ramble sends each note to your agent, or any webhook."
        }
    }
}

private struct IntroBeatPage: View {
    let beat: IntroBeat

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 12)

            Group {
                switch beat {
                case .sayIt: SayItIllustration()
                case .leavePhone: LeavePhoneIllustration()
                case .agentHandles: AgentHandlesIllustration()
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 300)

            Spacer(minLength: 12)

            VStack(alignment: .leading, spacing: 10) {
                OnboardingHeadline(size: 34, alignment: .leading) { beat.headline }
                    .frame(maxWidth: .infinity, alignment: .leading)
                OnboardingBody(text: beat.body, maxWidth: nil, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.bottom, 8)
        }
    }
}

// MARK: - Segment bar

private struct IntroSegmentBar: View {
    let count: Int
    let current: Int
    let fill: CGFloat

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(Color.obHair)
                    .overlay(alignment: .leading) {
                        GeometryReader { geo in
                            Capsule()
                                .fill(Color.brandAmber)
                                .frame(width: geo.size.width * progress(for: index))
                        }
                    }
                    .frame(height: 3)
            }
        }
        .accessibilityHidden(true)
    }

    private func progress(for index: Int) -> CGFloat {
        if index < current { return 1 }
        if index == current { return fill }
        return 0
    }
}

// MARK: - Watch drawing

/// The watch's own amber. The watch UI is always dark, so this never changes.
let onboardingWatchAmber = Color(red: 245 / 255, green: 158 / 255, blue: 11 / 255)

/// A small Apple Watch: bands, case and a black face with `content` on it.
struct OnboardingWatchFrame<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                UnevenRoundedRectangle(topLeadingRadius: 10, topTrailingRadius: 10)
                    .fill(Color(white: 0.2))
                    .frame(width: 64, height: 22)
                Spacer(minLength: 0)
                UnevenRoundedRectangle(bottomLeadingRadius: 10, bottomTrailingRadius: 10)
                    .fill(Color(white: 0.2))
                    .frame(width: 64, height: 22)
            }
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .fill(Color(white: 0.12))
                .frame(width: 124, height: 148)
            RoundedRectangle(cornerRadius: 29, style: .continuous)
                .fill(Color.black)
                .frame(width: 108, height: 132)
            content()
        }
        .frame(width: 124, height: 184)
        .accessibilityHidden(true)
    }
}

/// The watch's record button at rest: amber ring around a filled circle.
struct OnboardingRecordGlyph: View {
    var body: some View {
        ZStack {
            Circle().stroke(onboardingWatchAmber, lineWidth: 4).frame(width: 66, height: 66)
            Circle().fill(onboardingWatchAmber).frame(width: 50, height: 50)
        }
    }
}

// MARK: - Beat 1: say it

private enum RecordPhase: CaseIterable {
    case idle, recording, saved
}

private struct SayItIllustration: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            face(.idle).scaleEffect(1.4)
        } else {
            PhaseAnimator(RecordPhase.allCases) { phase in
                face(phase).scaleEffect(1.4)
            } animation: { phase in
                switch phase {
                case .idle: return .easeInOut(duration: 0.3).delay(1.0)
                case .recording: return .easeInOut(duration: 0.3).delay(1.2)
                case .saved: return .spring(response: 0.35, dampingFraction: 0.7).delay(2.4)
                }
            }
        }
    }

    private func face(_ phase: RecordPhase) -> some View {
        OnboardingWatchFrame {
            ZStack {
                Circle()
                    .stroke(onboardingWatchAmber, lineWidth: 4)
                    .frame(width: 66, height: 66)
                Circle()
                    .fill(onboardingWatchAmber)
                    .frame(width: 50, height: 50)
                    .scaleEffect(phase == .idle ? 1 : 0.01)
                LiveBars()
                    .opacity(phase == .recording ? 1 : 0)
                Circle()
                    .fill(onboardingWatchAmber)
                    .frame(width: 66, height: 66)
                    .overlay {
                        Image(systemName: "checkmark")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(Color.black)
                    }
                    .scaleEffect(phase == .saved ? 1 : 0.6)
                    .opacity(phase == .saved ? 1 : 0)
            }
        }
    }
}

/// Three bars that move like the watch's live audio level.
private struct LiveBars: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { index in
                    Capsule()
                        .fill(onboardingWatchAmber)
                        .frame(width: 5, height: 8 + 14 * abs(sin(t * 5 + Double(index) * 0.9)))
                }
            }
        }
    }
}

// MARK: - Beat 2: leave your phone behind

private enum LeavePhase: CaseIterable {
    case empty, one, two, three, synced

    var queued: Int {
        switch self {
        case .empty: return 0
        case .one: return 1
        case .two: return 2
        case .three, .synced: return 3
        }
    }
}

private struct LeavePhoneIllustration: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            scene(.three)
        } else {
            PhaseAnimator(LeavePhase.allCases) { phase in
                scene(phase)
            } animation: { phase in
                switch phase {
                case .empty: return .easeInOut(duration: 0.2).delay(1.6)
                case .one, .two, .three: return .spring(response: 0.3, dampingFraction: 0.7).delay(0.6)
                case .synced: return .easeInOut(duration: 0.6).delay(1.0)
                }
            }
        }
    }

    private func scene(_ phase: LeavePhase) -> some View {
        let synced = phase == .synced
        return VStack(spacing: 18) {
            HStack {
                Text("No phone nearby")
                    .foregroundStyle(Color.obInkFaint)
                    .opacity(synced ? 0 : 1)
                Spacer()
                Text("Caught up")
                    .foregroundStyle(Color.brandAmber)
                    .opacity(synced ? 1 : 0)
            }
            .font(.system(size: 13, weight: .semibold))

            HStack(spacing: 0) {
                OnboardingWatchFrame { OnboardingRecordGlyph() }

                VStack(spacing: 8) {
                    ForEach(0..<3, id: \.self) { index in
                        Circle()
                            .fill(Color.brandAmber)
                            .frame(width: 12, height: 12)
                            .opacity(index < phase.queued ? 1 : 0)
                            .scaleEffect(index < phase.queued ? 1 : 0.4)
                    }
                }
                .offset(x: synced ? 80 : 0)
                .opacity(synced ? 0 : 1)
                .padding(.leading, 14)

                Spacer(minLength: 16)

                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(synced ? Color.brandAmber : Color.obHair, lineWidth: 3)
                    .frame(width: 84, height: 156)
                    .overlay {
                        Text("later")
                            .font(.system(size: 15, design: .serif).italic())
                            .foregroundStyle(Color.obInkFaint)
                    }
            }
        }
        .frame(maxWidth: 320)
        .accessibilityHidden(true)
    }
}

// MARK: - Beat 3: your agent handles it

private struct AgentHandlesIllustration: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let rows: [(String, String)] = [
        ("Oat milk", "To-do"),
        ("Call Sam", "1:00 PM"),
        ("Walking 1:1s", "Idea"),
    ]

    var body: some View {
        if reduceMotion {
            card(done: rows.count)
        } else {
            PhaseAnimator([0, 1, 2, 3]) { done in
                card(done: done)
            } animation: { done in
                done == 0
                    ? .easeInOut(duration: 0.2).delay(1.8)
                    : .spring(response: 0.3, dampingFraction: 0.7).delay(0.7)
            }
        }
    }

    private func card(done: Int) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.brandAmber)
                    .frame(width: 26, height: 26)
                    .background(Color.brandAmberSoft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                Text("Your agent")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.obInkSoft)
            }

            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                HStack(spacing: 10) {
                    Image(systemName: index < done ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20))
                        .foregroundStyle(index < done ? Color.brandAmber : Color.obHair)
                        .contentTransition(.symbolEffect(.replace))
                    Text(row.0)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Color.obInk)
                    Spacer()
                    Text(row.1)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.obInkFaint)
                }
            }
        }
        .padding(18)
        .frame(width: 290)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: .black.opacity(0.07), radius: 15, y: 10)
        )
        .accessibilityHidden(true)
    }
}

#Preview {
    OnboardingIntroStep(onContinue: {})
        .background(Color(.systemGroupedBackground))
}
