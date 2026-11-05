//
//  WatchRecordingsListView.swift
//  watch Watch App
//
//  Recent notes, grouped by what needs you. Counts and reasons live here,
//  not on the home screen.
//

import SwiftUI

struct WatchRecordingsListView: View {
    @StateObject private var history = WatchRecordingHistory.shared
    @StateObject private var syncQueue = WatchSyncQueue.shared
    @StateObject private var connectivity = WatchConnectivityService.shared

    var body: some View {
        let notes = WatchDelivery.notes()
        let needsYou = notes.filter { $0.state.needsYou }
        let waiting = notes.filter { [.waiting, .moving, .reachedPhone].contains($0.state) }
        let onPhone = notes.filter { $0.state == .onPhone }

        Group {
            if notes.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "waveform")
                        .font(.title2)
                    Text("No notes yet")
                        .font(.footnote)
                }
                .foregroundStyle(.secondary)
            } else {
                List {
                    if !needsYou.isEmpty {
                        Section {
                            ForEach(needsYou) { WatchRecordingRow(entry: $0.entry, state: $0.state) }
                        } header: {
                            Text("Needs you · \(needsYou.count)").foregroundStyle(.red)
                        }
                    }
                    if !waiting.isEmpty {
                        Section("Waiting · \(waiting.count)") {
                            ForEach(waiting) { WatchRecordingRow(entry: $0.entry, state: $0.state) }
                        }
                    }
                    if !onPhone.isEmpty {
                        Section("On iPhone") {
                            ForEach(onPhone) { WatchRecordingRow(entry: $0.entry, state: $0.state) }
                        }
                    }
                }
            }
        }
        .navigationTitle("Recent")
        .onAppear {
            // Seeing a lost note is all there is to do about it
            let lost = notes.filter { $0.state == .lost }.map(\.id)
            history.markLostSeen(lost)
        }
    }
}

struct WatchRecordingRow: View {
    let entry: WatchRecordingHistoryEntry
    let state: WatchDeliveryState

    var body: some View {
        HStack(spacing: 8) {
            icon
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.createdAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                    .font(.footnote.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let reason {
                    Text(reason)
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
            }
            Spacer(minLength: 2)
            Text(WatchFormat.duration(entry.duration))
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(accessibilityState)
    }

    @ViewBuilder
    private var icon: some View {
        switch state {
        case .onPhone:
            Image(systemName: "checkmark.circle").foregroundStyle(.secondary)
        case .moving:
            ProgressView().controlSize(.mini)
        case .waiting:
            Image(systemName: "clock").foregroundStyle(.secondary)
        case .reachedPhone:
            Image(systemName: "iphone").foregroundStyle(.secondary)
        case .stuck, .lost:
            Image(systemName: "exclamationmark.circle").foregroundStyle(.red)
        }
    }

    private var reason: String? {
        switch state {
        case .stuck(let since): return WatchFormat.waitingReason(since: since)
        case .lost: return "Audio lost"
        default: return nil
        }
    }

    private var accessibilityState: String {
        switch state {
        case .onPhone: return "On iPhone"
        case .moving: return "Sending to iPhone"
        case .waiting: return "Waiting for iPhone"
        case .reachedPhone: return "Reached iPhone, waiting for Ramble to save it"
        case .stuck(let since): return WatchFormat.waitingReason(since: since)
        case .lost: return "Audio lost"
        }
    }
}

/// The words behind a bar alert: what happened and how to fix it.
struct WatchAlertDetailView: View {
    let alert: WatchAlert

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Label(alert.detailTitle, systemImage: alert.symbol)
                    .font(.headline)
                    .foregroundStyle(alert.isBlocking ? Color.red : Color.primary)
                ForEach(alert.detailBody, id: \.self) { paragraph in
                    Text(paragraph)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#Preview {
    NavigationStack {
        WatchRecordingsListView()
    }
}
