//
//  SetupCardView.swift
//  Ramble
//

import SwiftUI

struct SetupCardView: View {
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "icloud.slash")
                .font(.system(size: 28))
                .foregroundColor(.secondary)

            Text("Backend not configured")
                .font(.headline)

            Text("Set up your API to sync recordings")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Button("Setup", action: onOpenSettings)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

#Preview {
    SetupCardView(onOpenSettings: {})
}
