//
//  SettingsButtonView.swift
//  Ramble
//

import SwiftUI

struct SettingsButtonView: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "gearshape.fill")
                .font(.title3)
                .foregroundColor(.secondary)
                .frame(width: 36, height: 36)
                .background(
                    Circle()
                        .fill(Color(uiColor: .secondarySystemBackground))
                )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    SettingsButtonView {}
}
