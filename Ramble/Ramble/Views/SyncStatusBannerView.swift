//
//  SyncStatusBannerView.swift
//  Ramble
//
//  One-line summary of recordings that haven't reached their destination yet.
//  Hidden by the caller when every count is zero.
//

import SwiftUI

struct SyncStatusBannerView: View {
    let transcribingCount: Int
    let sendingCount: Int
    let waitingCount: Int
    let failedCount: Int
    var agentName: String = "Muse"

    static func isVisible(transcribing: Int, sending: Int, waiting: Int, failed: Int) -> Bool {
        transcribing + sending + waiting + failed > 0
    }

    private var parts: [String] {
        var parts: [String] = []
        if transcribingCount > 0 { parts.append("\(transcribingCount) transcribing") }
        if sendingCount > 0 { parts.append("\(sendingCount) sending") }
        if waitingCount > 0 { parts.append("\(waitingCount) waiting for \(agentName)") }
        if failedCount > 0 { parts.append("\(failedCount) failed") }
        return parts
    }

    var body: some View {
        HStack(spacing: 8) {
            if failedCount > 0 {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            } else if transcribingCount + sendingCount > 0 {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: "clock")
                    .foregroundStyle(.blue)
            }

            Text(parts.joined(separator: " · "))
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(failedCount > 0
                    ? Color.orange.opacity(0.12)
                    : Color(uiColor: .secondarySystemGroupedBackground))
        )
        // Opaque base so list rows scrolling underneath don't show through.
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
        .padding(.horizontal)
        .padding(.vertical, 4)
    }
}

#Preview {
    VStack {
        SyncStatusBannerView(transcribingCount: 1, sendingCount: 2, waitingCount: 0, failedCount: 0)
        SyncStatusBannerView(transcribingCount: 0, sendingCount: 0, waitingCount: 3, failedCount: 0)
        SyncStatusBannerView(transcribingCount: 0, sendingCount: 1, waitingCount: 2, failedCount: 1)
    }
}
