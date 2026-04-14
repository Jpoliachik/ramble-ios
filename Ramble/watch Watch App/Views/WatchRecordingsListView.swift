//
//  WatchRecordingsListView.swift
//  watch Watch App
//

import SwiftUI

struct WatchRecordingsListView: View {
    @StateObject private var history = WatchRecordingHistory.shared
    @StateObject private var syncQueue = WatchSyncQueue.shared

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
                List(history.entries) { entry in
                    WatchRecordingRow(
                        entry: entry,
                        isPending: syncQueue.jobs.contains(where: { $0.id == entry.id })
                    )
                }
            }
        }
        .navigationTitle("Recordings")
    }
}

struct WatchRecordingRow: View {
    let entry: WatchRecordingHistoryEntry
    let isPending: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.createdAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                    .font(.caption)
                    .fontWeight(.medium)
                Text(formatDuration(entry.duration))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            syncIndicator
        }
    }

    @ViewBuilder
    private var syncIndicator: some View {
        if entry.syncedAt != nil {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.body)
        } else if isPending {
            Image(systemName: "arrow.up.circle")
                .foregroundStyle(.orange)
                .font(.body)
        } else {
            Image(systemName: "exclamationmark.circle")
                .foregroundStyle(.red)
                .font(.body)
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = Int(duration)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}

#Preview {
    NavigationStack {
        WatchRecordingsListView()
    }
}
