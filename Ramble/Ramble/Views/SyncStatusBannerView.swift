//
//  SyncStatusBannerView.swift
//  Ramble
//

import SwiftUI

struct SyncStatusBannerView: View {
    let pendingCount: Int
    let failedCount: Int
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                if failedCount > 0 {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("\(failedCount) transcription\(failedCount == 1 ? "" : "s") failed")
                        .font(.subheadline.weight(.medium))
                } else {
                    ProgressView()
                        .controlSize(.small)
                    Text("\(pendingCount) recording\(pendingCount == 1 ? "" : "s") transcribing...")
                        .font(.subheadline.weight(.medium))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(failedCount > 0
                        ? Color.orange.opacity(0.12)
                        : Color(uiColor: .secondarySystemGroupedBackground))
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
        .padding(.vertical, 4)
    }
}

#Preview {
    VStack {
        SyncStatusBannerView(pendingCount: 3, failedCount: 0, onTap: {})
        SyncStatusBannerView(pendingCount: 1, failedCount: 2, onTap: {})
    }
}
