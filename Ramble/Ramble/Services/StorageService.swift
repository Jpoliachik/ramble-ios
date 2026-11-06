//
//  StorageService.swift
//  Ramble
//

import Foundation

final class StorageService {
    static let shared = StorageService()

    static var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static var audioDirectory: URL {
        documentsDirectory.appendingPathComponent("audio", isDirectory: true)
    }

    private let recordingsFile = documentsDirectory.appendingPathComponent("recordings.json")
    /// IDs the person deleted, so a later transcript or watch delivery never
    /// brings the note back (specs/phone.md "Deleting a note").
    private let deletedFile = documentsDirectory.appendingPathComponent("deleted_recordings.json")
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        createAudioDirectoryIfNeeded()
    }

    private func createAudioDirectoryIfNeeded() {
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: Self.audioDirectory.path) {
            try? fileManager.createDirectory(
                at: Self.audioDirectory,
                withIntermediateDirectories: true
            )
        }
    }

    func loadRecordings() -> [Recording] {
        guard FileManager.default.fileExists(atPath: recordingsFile.path),
              let data = try? Data(contentsOf: recordingsFile),
              let recordings = try? decoder.decode([Recording].self, from: data) else {
            return []
        }
        return recordings.sorted { $0.createdAt > $1.createdAt }
    }

    func recording(withId id: UUID) -> Recording? {
        loadRecordings().first { $0.id == id }
    }

    static let recordingsDidChangeNotification = Notification.Name("recordingsDidChange")

    func saveRecordings(_ recordings: [Recording]) {
        guard let data = try? encoder.encode(recordings) else { return }
        try? data.write(to: recordingsFile)
        NotificationCenter.default.post(name: Self.recordingsDidChangeNotification, object: nil)
    }

    /// Returns false if a recording with this id already exists or was deleted.
    @discardableResult
    func addRecording(_ recording: Recording) -> Bool {
        guard !isDeleted(recording.id) else { return false }
        var recordings = loadRecordings()
        guard !recordings.contains(where: { $0.id == recording.id }) else { return false }
        recordings.insert(recording, at: 0)
        saveRecordings(recordings)
        return true
    }

    func updateRecording(_ recording: Recording) {
        var recordings = loadRecordings()
        if let index = recordings.firstIndex(where: { $0.id == recording.id }) {
            recordings[index] = recording
            saveRecordings(recordings)
        }
    }

    /// Changes one recording in place. Returns the result, or nil if it's gone.
    @discardableResult
    func update(_ id: UUID, _ change: (inout Recording) -> Void) -> Recording? {
        var recordings = loadRecordings()
        guard let index = recordings.firstIndex(where: { $0.id == id }) else { return nil }
        change(&recordings[index])
        saveRecordings(recordings)
        return recordings[index]
    }

    func deleteRecording(_ recording: Recording) {
        markDeleted([recording.id])
        var recordings = loadRecordings()
        recordings.removeAll { $0.id == recording.id }
        saveRecordings(recordings)

        try? FileManager.default.removeItem(at: recording.audioFileURL)
    }

    func deleteAllRecordings() {
        let recordings = loadRecordings()
        markDeleted(recordings.map(\.id))
        for recording in recordings {
            try? FileManager.default.removeItem(at: recording.audioFileURL)
        }
        saveRecordings([])
    }

    // MARK: - Deleted IDs

    func isDeleted(_ id: UUID) -> Bool {
        deletedIDs().contains(id)
    }

    func deletedIDs() -> Set<UUID> {
        guard let data = try? Data(contentsOf: deletedFile),
              let ids = try? decoder.decode(Set<UUID>.self, from: data) else { return [] }
        return ids
    }

    private func markDeleted(_ ids: [UUID]) {
        guard !ids.isEmpty else { return }
        let all = deletedIDs().union(ids)
        guard let data = try? encoder.encode(all) else { return }
        try? data.write(to: deletedFile)
    }
}
