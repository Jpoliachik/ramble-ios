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

    static let recordingsDidChangeNotification = Notification.Name("recordingsDidChange")

    func saveRecordings(_ recordings: [Recording]) {
        guard let data = try? encoder.encode(recordings) else { return }
        try? data.write(to: recordingsFile)
        NotificationCenter.default.post(name: Self.recordingsDidChangeNotification, object: nil)
    }

    func addRecording(_ recording: Recording) {
        var recordings = loadRecordings()
        recordings.insert(recording, at: 0)
        saveRecordings(recordings)
    }

    func updateRecording(_ recording: Recording) {
        var recordings = loadRecordings()
        if let index = recordings.firstIndex(where: { $0.id == recording.id }) {
            recordings[index] = recording
            saveRecordings(recordings)
        }
    }

    func deleteRecording(_ recording: Recording) {
        var recordings = loadRecordings()
        recordings.removeAll { $0.id == recording.id }
        saveRecordings(recordings)

        try? FileManager.default.removeItem(at: recording.audioFileURL)
    }

    func deleteAllRecordings() {
        let recordings = loadRecordings()
        for recording in recordings {
            try? FileManager.default.removeItem(at: recording.audioFileURL)
        }
        saveRecordings([])
    }
}
