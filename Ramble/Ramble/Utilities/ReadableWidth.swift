//
//  ReadableWidth.swift
//  Ramble
//
//  Keeps content at a readable width on wide screens (iPad). On iPhone
//  nothing changes.
//

import SwiftUI

enum ReadableWidth {
    /// The widest a list's rows, or the home header, get.
    static let max: CGFloat = 680
}

private struct ReadableListWidth: ViewModifier {
    @State private var inset: CGFloat?

    func body(content: Content) -> some View {
        content
            .contentMargins(.horizontal, inset, for: .scrollContent)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
                inset = width > ReadableWidth.max + 80 ? (width - ReadableWidth.max) / 2 : nil
            }
    }
}

extension View {
    /// For a List or Form: side margins that hold its rows to `ReadableWidth.max`.
    func readableListWidth() -> some View {
        modifier(ReadableListWidth())
    }
}
