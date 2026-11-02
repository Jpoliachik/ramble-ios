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

    /// Jobs not currently handed to WatchConnectivity, i.e. ones a manual retry would send.
    private var hasIdleJobs: Bool {
        syncQueue.jobs.contains { !connectivity.inFlightIDs.contains($0.id) }
    }

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
                            WatchRecordingRow(entry: entry, state: state(for: entry))
                        }
                    } footer: {
                        if !syncQueue.jobs.isEmpty {
                            Text("Recordings stay on your watch until your iPhone has them.")
                        }
                    }

                    if hasIdleJobs {
                        Button("Try again") {
                            connectivity.retryPendingTransfers()
                        }
                        .foregroundStyle(Color.brandRed)
                    }
                }
            }
        }
        .navigationTitle("Recent")
    }

    private func state(for entry: WatchRecordingHistoryEntry) -> WatchRecordingState {
        WatchRecordingState.resolve(
            entry: entry,
            job: syncQueue.jobs.first { $0.id == entry.id },
            isInFlight: connectivity.inFlightIDs.contains(entry.id),
            isPhoneReachable: connectivity.isPhoneReachable
        )
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
