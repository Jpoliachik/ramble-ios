//
//  WatchRecordingsListView.swift
//  watch Watch App
//
//  Recent: the notes recorded on this watch, grouped by what needs you.
//  Counts and reasons live here, not on the home screen. Rows aren't
//  tappable; the full history is on the iPhone.
//

import SwiftUI

struct WatchRecordingsListView: View {
    @StateObject private var store = WatchNoteStore.shared
    @StateObject private var relay = WatchRelayService.shared

    var body: some View {
        let notes = WatchRecent.notes()
        let needsYou = notes.filter { $0.display.section == .needsYou }
        let waiting = notes.filter { $0.display.section == .waiting }
        let done = notes.filter { $0.display.section == .done }

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
                            ForEach(needsYou) { WatchRecordingRow(note: $0) }
                        } header: {
                            Text("Needs you · \(needsYou.count)").foregroundStyle(.red)
                        }
                    }
                    if !waiting.isEmpty {
                        Section("Waiting · \(waiting.count)") {
                            ForEach(waiting) { WatchRecordingRow(note: $0) }
                        }
                    }
                    if !done.isEmpty {
                        Section("Done") {
                            ForEach(done) { WatchRecordingRow(note: $0) }
                        }
                    }
                }
            }
        }
        .navigationTitle("Recent")
        .onAppear {
            // Failed, refused and lost notes leave Recent 24 hours after the
            // person first sees them; a seen lost note stops the red dot.
            let seen = notes.filter { $0.display.isFinalProblem }.map(\.id)
            relay.markSeen(seen)
        }
    }
}

struct WatchRecordingRow: View {
    let note: WatchNote

    private var record: WatchNoteRecord { note.record }

    var body: some View {
        HStack(spacing: 8) {
            icon
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(record.recordedAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                        .font(.footnote.weight(.medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 2)
                    Text(WatchFormat.duration(record.duration))
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                if let line = note.display.line {
                    Text(line)
                        .font(.caption2)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundStyle(note.display.section == .needsYou ? Color.red : Color.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(accessibilityState)
    }

    @ViewBuilder
    private var icon: some View {
        switch note.display {
        case .waiting:
            Image(systemName: "clock").foregroundStyle(.secondary)
        case .uploading, .transcribing:
            ProgressView().controlSize(.mini)
        case .done:
            Image(systemName: "checkmark").foregroundStyle(.secondary)
        case .silent:
            Image(systemName: "waveform.slash").foregroundStyle(.secondary)
        case .heldUnlock, .stuck, .failed, .lost, .tooLong, .couldntSend:
            Image(systemName: "exclamationmark.circle").foregroundStyle(.red)
        }
    }

    private var accessibilityState: String {
        switch note.display {
        case .waiting: return "Waiting to send"
        case .uploading: return "Sending"
        case .transcribing: return "Transcribing"
        default: return note.display.line ?? "Done"
        }
    }
}

/// The words behind a bar alert: what happened and how it resolves.
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
