//
//  WatchRecordingsListView.swift
//  watch Watch App
//

import Combine
import SwiftUI

struct WatchRecordingsListView: View {
    @StateObject private var history = WatchRecordingHistory.shared
    @StateObject private var syncQueue = WatchSyncQueue.shared
    @StateObject private var connectivity = WatchConnectivityService.shared

    var body: some View {
        Group {
            if history.entries.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "waveform")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("No recordings yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                List {
                    Section {
                        ForEach(history.entries) { entry in
                            WatchRecordingRow(
                                entry: entry,
                                state: .resolve(entry, syncQueue: syncQueue, connectivity: connectivity)
                            )
                        }
                    } footer: {
                        if !syncQueue.jobs.isEmpty {
                            Text("Recordings stay on your watch until your iPhone has them.")
                        }
                    }
                }
            }
        }
        .navigationTitle("Recent")
    }
}

struct WatchRecordingRow: View {
    let entry: WatchRecordingHistoryEntry
    let state: WatchRecordingState

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(entry.createdAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                    .font(.caption)
                    .fontWeight(.medium)
                Spacer()
                Text(WatchFormat.duration(entry.duration))
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Label(state.label, systemImage: state.symbol)
                .font(.caption2)
                .foregroundStyle(state.tint)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    NavigationStack {
        WatchRecordingsListView()
    }
}
