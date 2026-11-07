//
//  WatchNoteStore.swift
//  watch Watch App
//
//  Every note this watch recorded and still keeps, persisted as JSON. A
//  note leaves the store only once it has left Recent and its audio is
//  gone; the audio is never deleted because uploads fail.
//

import Combine
import Foundation

@MainActor
final class WatchNoteStore: ObservableObject {
    static let shared = WatchNoteStore()

    /// Newest first.
    @Published private(set) var notes: [WatchNoteRecord] = []
    /// The first-launch hint stops for good once any note has been saved.
    @Published private(set) var hasEverSavedNote: Bool

    static let maxRecent = 50

    private static let hasSavedKey = "hasSavedFirstNote"

    nonisolated static var documentsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private static var fileURL: URL {
        documentsURL.appendingPathComponent("watch_notes.json")
    }

    private init() {
        hasEverSavedNote = UserDefaults.standard.bool(forKey: Self.hasSavedKey)
        load()
    }

    // MARK: - Reading

    func note(_ id: UUID) -> WatchNoteRecord? {
        notes.first { $0.id == id }
    }

    /// Notes listed in Recent.
    var recent: [WatchNoteRecord] {
        notes.filter { !$0.hiddenFromRecent }
    }

    var audioFileNames: Set<String> {
        Set(notes.filter { !$0.audioDeleted }.map(\.audioFileName))
    }

    // MARK: - Writing

    func add(_ record: WatchNoteRecord) {
        guard !notes.contains(where: { $0.id == record.id }) else { return }
        notes.insert(record, at: 0)
        if !hasEverSavedNote {
            hasEverSavedNote = true
            UserDefaults.standard.set(true, forKey: Self.hasSavedKey)
        }
        save()
    }

    /// Changes one note and saves. Returns the note as it was and as it is.
    @discardableResult
    func update(_ id: UUID, _ change: (inout WatchNoteRecord) -> Void) -> (before: WatchNoteRecord, after: WatchNoteRecord)? {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return nil }
        let before = notes[index]
        var after = before
        change(&after)
        guard after != before else { return (before, after) }
        notes[index] = after
        save()
        return (before, after)
    }

    func remove(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        notes.removeAll { ids.contains($0.id) }
        save()
    }

    // MARK: - Persistence

    private func load() {
        let url = Self.fileURL
        if FileManager.default.fileExists(atPath: url.path) {
            guard let data = try? Data(contentsOf: url),
                  let decoded = try? JSONDecoder().decode([WatchNoteRecord].self, from: data)
            else { return }
            notes = decoded
            return
        }
        migrateFromPhoneRoutedQueue()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(notes) else { return }
        try? data.write(to: Self.fileURL, options: .atomic)
    }

    // MARK: - Migration

    /// A job from the earlier build's queue, which waited for the iPhone.
    private struct LegacyJob: Decodable {
        let id: UUID
        let audioFileName: String
        let createdAt: Date
        let duration: TimeInterval
    }

    private struct LegacyHistoryEntry: Decodable {
        let id: UUID
    }

    /// Notes the earlier build still held for the iPhone now upload
    /// straight to the server instead. Notes the iPhone already confirmed
    /// were transcribed there and are left alone.
    private func migrateFromPhoneRoutedQueue() {
        let queueURL = Self.documentsURL.appendingPathComponent("watch_sync_queue.json")
        let historyURL = Self.documentsURL.appendingPathComponent("watch_recording_history.json")

        if let data = try? Data(contentsOf: historyURL),
           let history = try? JSONDecoder().decode([LegacyHistoryEntry].self, from: data),
           !history.isEmpty {
            hasEverSavedNote = true
            UserDefaults.standard.set(true, forKey: Self.hasSavedKey)
        }

        if let data = try? Data(contentsOf: queueURL),
           let jobs = try? JSONDecoder().decode([LegacyJob].self, from: data) {
            let now = Date()
            notes = jobs
                .filter { FileManager.default.fileExists(atPath: Self.documentsURL.appendingPathComponent($0.audioFileName).path) }
                .sorted { $0.createdAt > $1.createdAt }
                .map {
                    WatchNoteRecord(
                        id: $0.id,
                        recordedAt: $0.createdAt,
                        duration: $0.duration,
                        audioFileName: $0.audioFileName,
                        now: now
                    )
                }
            if !notes.isEmpty {
                hasEverSavedNote = true
                UserDefaults.standard.set(true, forKey: Self.hasSavedKey)
            }
        }

        save()
        try? FileManager.default.removeItem(at: queueURL)
        try? FileManager.default.removeItem(at: historyURL)
        UserDefaults.standard.removeObject(forKey: "seenLostNoteIDs")
    }
}
