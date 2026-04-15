//
//  SettingsButtonView.swift
//  Ramble

import SwiftUI

struct SettingsButtonView: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "gearshape")
                .font(.body.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 40, height: 40)
                .background(.ultraThinMaterial, in: Circle())
                .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
        }
        .buttonStyle(.plain)
        .contentShape(Circle().scale(1.5))
    }
}

#Preview {
    SettingsButtonView {}
}
