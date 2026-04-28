//
//  OnboardingComponents.swift
//  Ramble
//

import SwiftUI

// MARK: - Step state

enum OnboardingStep: Int, CaseIterable {
    case welcome
    case record
    case transcribe
    case send

    /// 1-based position in the 3-step body. Welcome returns nil (no dots shown).
    var progressIndex: Int? {
        switch self {
        case .welcome: return nil
        case .record: return 1
        case .transcribe: return 2
        case .send: return 3
        }
    }

    var previous: OnboardingStep? {
        switch self {
        case .welcome: return nil
        case .record: return .welcome
        case .transcribe: return .record
        case .send: return .transcribe
        }
    }

    static let bodyStepCount = 3
}

// MARK: - Design tokens

extension Color {
    static let obInk = Color("onboarding-ink")
    static let obInkSoft = Color("onboarding-ink-soft")
    static let obInkFaint = Color("onboarding-ink-faint")
    static let obHair = Color("onboarding-hair")
}

enum OnboardingFont {
    /// New York serif headline — used at 34pt for steps 2-4 and 48pt for the welcome screen.
    static func serifHeadline(size: CGFloat) -> Font {
        .system(size: size, design: .serif).weight(.medium)
    }

    static let body: Font = .system(size: 16)
    static let bodyLarge: Font = .system(size: 17)
    static let sectionHeader: Font = .system(size: 12, weight: .medium)
}

// MARK: - Page chrome

/// Scrollable body container for an onboarding step with an optional pinned
/// bottom bar (typically the primary CTA). The body fills the area above the
/// bottom bar; if its content overflows the body scrolls. The persistent nav
/// row lives in `OnboardingView` so it doesn't get re-mounted between steps.
struct OnboardingPage<Content: View, BottomBar: View>: View {
    @ViewBuilder let content: () -> Content
    @ViewBuilder let bottomBar: () -> BottomBar

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                ScrollView {
                    VStack(spacing: 0) {
                        content()
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: geo.size.height, alignment: .top)
                }
                .scrollBounceBehavior(.basedOnSize)
            }

            bottomBar()
        }
    }
}

extension OnboardingPage where BottomBar == EmptyView {
    init(@ViewBuilder content: @escaping () -> Content) {
        self.init(content: content, bottomBar: { EmptyView() })
    }
}

/// Persistent nav row: back chevron + segmented progress bar. Owned by
/// `OnboardingView` so the row stays mounted across step transitions and
/// only the active progress dot animates.
struct OnboardingNavRow: View {
    let activeStep: Int
    let onBack: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button {
                HapticService.buttonTap()
                onBack()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Color.brandRed)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")

            Spacer()

            OnboardingProgressBar(activeStep: activeStep)

            Spacer()

            // Mirrors the back button width so the dots stay centered.
            Color.clear.frame(width: 44, height: 1)
        }
        .frame(height: 40)
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }
}

// MARK: - Progress bar (segmented pill)

struct OnboardingProgressBar: View {
    /// 1-based: 1, 2, or 3.
    let activeStep: Int

    private let dotSize: CGFloat = 6
    private let activeWidth: CGFloat = 20
    private let spacing: CGFloat = 6

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(1...OnboardingStep.bodyStepCount, id: \.self) { index in
                Capsule()
                    .fill(index <= activeStep ? Color.brandRed : Color.obHair)
                    .frame(width: index == activeStep ? activeWidth : dotSize, height: dotSize)
            }
        }
        .animation(.smooth(duration: 0.3), value: activeStep)
    }
}

// MARK: - Typographic primitives

/// Renders a serif headline. Pass a Text composition to mix italic accents:
///   `OnboardingHeadline(size: 34) { Text("First, ") + Text("let it hear you.").italic() }`
struct OnboardingHeadline: View {
    let size: CGFloat
    let alignment: TextAlignment
    let content: () -> Text

    init(size: CGFloat = 34, alignment: TextAlignment = .center, @ViewBuilder content: @escaping () -> Text) {
        self.size = size
        self.alignment = alignment
        self.content = content
    }

    var body: some View {
        content()
            .font(OnboardingFont.serifHeadline(size: size))
            .foregroundStyle(Color.obInk)
            .tracking(size >= 44 ? -1.0 : -0.6)
            .lineSpacing(0)
            .multilineTextAlignment(alignment)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct OnboardingBody: View {
    let text: String
    var maxWidth: CGFloat? = 320
    var alignment: TextAlignment = .center

    var body: some View {
        Text(text)
            .font(OnboardingFont.body)
            .foregroundStyle(Color.obInkSoft)
            .lineSpacing(2)
            .multilineTextAlignment(alignment)
            .frame(maxWidth: maxWidth)
    }
}

// MARK: - Wordmark (red dot + italic serif)

struct OnboardingWordmark: View {
    let size: CGFloat

    init(size: CGFloat = 48) {
        self.size = size
    }

    var body: some View {
        HStack(alignment: .center, spacing: size * 0.3) {
            Circle()
                .fill(Color.brandRed)
                .frame(width: size * 0.42, height: size * 0.42)

            Text("Ramble")
                .font(.system(size: size, design: .serif).italic())
                .fontWeight(.bold)
                .foregroundStyle(Color.obInk)
                .tracking(-0.5)
        }
    }
}

// MARK: - Illustration disc

/// 96pt soft-red disc for the step header illustration. The illustrations
/// already include the disc as part of the SVG, so this is just a sizer.
struct OnboardingIllustration: View {
    let name: String
    private let size: CGFloat = 96

    var body: some View {
        Image(name)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

// MARK: - Surface card

/// Rounded card filled with `secondarySystemBackground`. Used to group rows
/// outside of Form (e.g. onboarding steps). Inside Form, the system already
/// renders this surface as the row background — no explicit card needed.
struct BrandCard<Content: View>: View {
    var cornerRadius: CGFloat = 12
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            content()
        }
        .background(
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }
}

/// Hairline divider used between rows inside a `BrandCard`. Default leading
/// inset matches the icon column so the divider starts after the logo.
struct BrandRowDivider: View {
    var leadingInset: CGFloat = 50

    var body: some View {
        Rectangle()
            .fill(Color.obHair)
            .frame(height: 0.5)
            .padding(.leading, leadingInset)
    }
}

// MARK: - Plus action card

/// Bordered surface card with a circular plus icon — used for "Add a destination"
/// style entry points. Reused in onboarding and Settings.
struct BrandPlusActionCard: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button {
            HapticService.buttonTap()
            action()
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.brandRed)
                        .frame(width: 28, height: 28)
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color(.systemBackground))
                }
                Text(title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.obInk)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.obInkFaint)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.obInk.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Send visual (voice → endpoint pill, animated dot)

/// Illustrated explainer showing a spoken thought traveling to a webhook URL.
/// Reused in onboarding and Settings to anchor the webhook concept.
struct SendVisual: View {
    var voiceText: String = "So I was thinking we should do that thing."
    var endpointText: String = "my.api.com"

    private let cycleDuration: Double = 2.0

    var body: some View {
        HStack(spacing: 10) {
            voiceChip

            connector
                .frame(width: Self.connectorWidth, height: Self.connectorHeight)

            endpointChip
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 18)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.brandRedSoft)
        )
    }

    private var voiceChip: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "waveform")
                .font(.system(size: 12))
                .foregroundStyle(Color.brandRed)

            Text(voiceText)
                .font(.system(size: 10, design: .serif).italic())
                .foregroundStyle(Color.obInkSoft)
                .lineLimit(1)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.obInk, lineWidth: 1.5)
                )
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var connector: some View {
        // The ZStack already vertically centers its children, so the dot only
        // needs an x offset for travel — no y math required.
        let dotTravel = Self.connectorWidth - Self.dotSize - 6

        return TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let elapsed = context.date.timeIntervalSinceReferenceDate
            let progress = elapsed.truncatingRemainder(dividingBy: cycleDuration) / cycleDuration

            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.obInk)
                    .frame(height: 3)
                    .padding(.trailing, 8)

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.obInk)
                    .frame(maxWidth: .infinity, alignment: .trailing)

                Circle()
                    .fill(Color.brandRed)
                    .frame(width: Self.dotSize, height: Self.dotSize)
                    .offset(x: dotTravel * CGFloat(progress))
                    .opacity(travelOpacity(for: progress))
            }
        }
    }

    private static let connectorWidth: CGFloat = 64
    private static let connectorHeight: CGFloat = 24
    private static let dotSize: CGFloat = 14

    private func travelOpacity(for progress: Double) -> Double {
        switch progress {
        case ..<0.15: return progress / 0.15
        case 0.85...: return max(0, (1 - progress) / 0.15)
        default: return 1
        }
    }

    private var endpointChip: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "paperplane.fill")
                .font(.system(size: 11))
                .foregroundStyle(Color.brandRed)

            Text(endpointText)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color.obInkSoft)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.obInk, lineWidth: 1.5)
                )
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Buttons

struct OnboardingPrimaryButton: View {
    let title: String
    let isDisabled: Bool
    let isLoading: Bool
    let action: () -> Void

    init(
        title: String,
        isDisabled: Bool = false,
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.isDisabled = isDisabled
        self.isLoading = isLoading
        self.action = action
    }

    var body: some View {
        Button {
            HapticService.buttonTap()
            action()
        } label: {
            Group {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                } else {
                    Text(title)
                        .font(.system(size: 17, weight: .semibold))
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.brandRed)
            )
            .opacity(isDisabled ? 0.4 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled || isLoading)
    }
}

/// Full-width text button — surface fill, ink text, used as a "Maybe later" style action.
struct OnboardingSurfaceButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button {
            HapticService.buttonTap()
            action()
        } label: {
            Text(title)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Color.obInk)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.secondarySystemBackground))
                )
        }
        .buttonStyle(.plain)
    }
}

/// Centered red text link, full width.
struct OnboardingSecondaryLink: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button {
            HapticService.buttonTap()
            action()
        } label: {
            Text(title)
                .font(.system(size: 15))
                .foregroundStyle(Color.brandRed)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Section header (uppercase tracked label)

struct OnboardingSectionHeader: View {
    let title: String
    var trailing: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(OnboardingFont.sectionHeader)
                .tracking(1.0)
                .textCase(.uppercase)
                .foregroundStyle(Color.obInkFaint)

            Spacer()

            if let trailing {
                Text(trailing)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.obInkFaint)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
    }
}

// MARK: - Italic-red inline tag (e.g. "Required", "Recommended")

struct OnboardingItalicTag: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 13, design: .serif).italic().weight(.medium))
            .foregroundStyle(Color.brandRed)
    }
}

// MARK: - Appear-in animation

struct OnboardingAppearModifier: ViewModifier {
    let delay: Double
    @State private var visible = false

    func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .offset(y: visible ? 0 : 12)
            .onAppear {
                withAnimation(.easeOut(duration: 0.5).delay(delay)) {
                    visible = true
                }
            }
    }
}

extension View {
    func onboardingAppear(delay: Double = 0) -> some View {
        modifier(OnboardingAppearModifier(delay: delay))
    }
}
