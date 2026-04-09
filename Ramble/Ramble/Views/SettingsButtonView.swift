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
                .frame(width: 34, height: 34)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .contentShape(Circle().scale(1.5))
    }
}

#Preview {
    SettingsButtonView {}
}
