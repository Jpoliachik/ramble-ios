//
//  WatchRecordingHistory.swift
//  watch Watch App
//

import Combine
import Foundation

struct WatchRecordingHistoryEntry: Codable, Identifiable {
    let id: UUID
    let createdAt: Date
    let duration: TimeInterval
    var syncedAt: Date?
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
