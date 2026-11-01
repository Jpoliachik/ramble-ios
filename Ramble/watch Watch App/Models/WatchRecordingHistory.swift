//
//  WatchRecordingHistory.swift
//  watch Watch App
//

import Combine
import Foundation

/// What the phone has reported about a recording after it arrived.
///
/// The phone does not send these yet. Until it does, every recording the
/// phone has confirmed reads as `.received` ("Sent to iPhone"). Unknown raw
/// values decode as `.received` so a newer phone can't break the history file.
enum WatchPhoneStatus: String, Codable {
    case received
    case transcribing
    case transcribed
    case delivered
    case failed

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = WatchPhoneStatus(rawValue: raw) ?? .received
    }
}

struct WatchRecordingHistoryEntry: Codable, Identifiable {
    let id: UUID
    let createdAt: Date
    let duration: TimeInterval
    /// Set when WatchConnectivity confirms the file reached the phone.
    var syncedAt: Date?
    /// Set only when the phone reports progress. nil means "sent, nothing more known".
    var phoneStatus: WatchPhoneStatus?
}

@MainActor
final class WatchRecordingHistory: ObservableObject {
    static let shared = WatchRecordingHistory()

    @Published private(set) var entries: [WatchRecordingHistoryEntry] = []

    private static let maxEntries = 50

    private static var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("watch_recording_history.json")
    }

    private init() {
        load()
    }

    // MARK: - Public API

    func addEntry(id: UUID, createdAt: Date, duration: TimeInterval) {
        guard !entries.contains(where: { $0.id == id }) else { return }

        let entry = WatchRecordingHistoryEntry(
            id: id,
            createdAt: createdAt,
            duration: duration
        )
        entries.insert(entry, at: 0)

        if entries.count > Self.maxEntries {
            entries = Array(entries.prefix(Self.maxEntries))
        }
        save()
    }

    func markSynced(id: UUID) {
        guard let idx = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[idx].syncedAt = Date()
        save()
    }

    /// Record a status reported by the phone. Not called yet; ready for a
    /// phone→watch status message. A phone report also implies the file arrived.
    func updatePhoneStatus(id: UUID, status: WatchPhoneStatus) {
        guard let idx = entries.firstIndex(where: { $0.id == id }) else { return }
        if entries[idx].syncedAt == nil {
            entries[idx].syncedAt = Date()
        }
        entries[idx].phoneStatus = status
        save()
    }

    // MARK: - Persistence

    private func load() {
        let url = Self.fileURL
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([WatchRecordingHistoryEntry].self, from: data)
        else { return }
        entries = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: Self.fileURL)
    }
}
