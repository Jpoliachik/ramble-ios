//
//  TranscriptionModelRow.swift
//  Ramble
//

import SwiftUI

enum TranscriptionModelLogo {
    case system(String)
    case asset(String)
}

/// Shared row for picking a transcription model. Used in both the onboarding
/// Transcribe step and the Settings transcription section so both surfaces look
/// identical. The trailing slot has a fixed width so the row doesn't shift width
/// when a row toggles between selected (checkmark) and locked (lock).
struct TranscriptionModelRow: View {
    let title: String
    let subtitle: String
    let logo: TranscriptionModelLogo
    var isSelected: Bool = false
    var isLocked: Bool = false
    let onTap: () -> Void

    private let trailingSlotWidth: CGFloat = 24

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                logoView
                    .frame(width: 22, height: 22)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 17))
                        .foregroundStyle(Color.obInk)

                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.obInkFaint)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                trailingIndicator
                    .frame(width: trailingSlotWidth, height: trailingSlotWidth)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var logoView: some View {
        switch logo {
        case .system(let name):
            Image(systemName: name)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(Color.obInk)
        case .asset(let name):
            Image(name)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundStyle(Color.obInk)
        }
    }

    @ViewBuilder
    private var trailingIndicator: some View {
        if isSelected {
            Image(systemName: "checkmark")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.brandRed)
        } else if isLocked {
            Image(systemName: "lock.fill")
                .font(.system(size: 13))
                .foregroundStyle(Color.obInkFaint)
        }
    }
}

// MARK: - Model-aware row presets

/// Apple Speech row that always reads its label/subtitle/icon from the
/// `TranscriptionProvider.appleSpeech` model. Use anywhere the picker is shown
/// so onboarding and Settings render identically.
struct AppleSpeechRow: View {
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        TranscriptionModelRow(
            title: TranscriptionProvider.appleSpeech.displayName,
            subtitle: TranscriptionProvider.appleSpeech.subtitle,
            logo: .system(TranscriptionProvider.appleSpeech.iconName),
            isSelected: isSelected,
            onTap: onTap
        )
    }
}

/// Cloud model row driven entirely by `CloudModel`. Adding a new case to the
/// enum surfaces it in every picker automatically.
struct CloudModelRow: View {
    let model: CloudModel
    let isSelected: Bool
    let isLocked: Bool
    let onTap: () -> Void

    var body: some View {
        TranscriptionModelRow(
            title: model.displayName,
            subtitle: model.subtitle,
            logo: .asset(model.iconName),
            isSelected: isSelected,
            isLocked: isLocked,
            onTap: onTap
        )
    }
}
