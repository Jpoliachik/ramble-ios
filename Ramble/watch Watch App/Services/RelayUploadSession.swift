//
//  RelayUploadSession.swift
//  watch Watch App
//
//  The background URLSession that carries note audio to the relay. Each
//  upload is started from the file at the stop, while the app is still in
//  front, so nsurlsessiond can finish it after the wrist drops and the app
//  is suspended. Results are handed to WatchRelayService on the main actor.
//

import Foundation

/// What one finished upload task said. Built off the main actor.
nonisolated struct RelayUploadOutcome: Sendable {
    let noteID: UUID
    /// The token the request carried, so a 401 for a token already replaced
    /// doesn't mark the current one rejected.
    let token: String?
    /// Nil when the request never got an HTTP answer (offline, timeout).
    let status: Int?
    let body: Data
    let retryAfter: TimeInterval?
    let errorDescription: String?
}

nonisolated final class RelayUploadSession: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    static let identifier = "dev.goodloop.ramble.watch.upload"
    static let shared = RelayUploadSession()

    private let lock = NSLock()
    private var buffers: [Int: Data] = [:]
    private var finishedEvents = false
    private var session: URLSession!

    private override init() {
        super.init()
        let configuration = URLSessionConfiguration.background(withIdentifier: Self.identifier)
        configuration.sessionSendsLaunchEvents = true
        configuration.isDiscretionary = false
        // The relay may hold the answer up to 8 s for a quick transcript, and
        // clients must allow at least 30 s (relay-api.md).
        configuration.timeoutIntervalForRequest = 120
        // A task the system never manages to run is given up after a day and
        // started again by the retry passes, so nothing waits on it forever.
        configuration.timeoutIntervalForResource = 24 * 3600
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
    }

    /// `taskDescription` carries the note ID so a relaunched app can match
    /// results to notes.
    func upload(_ request: URLRequest, fromFile fileURL: URL, noteID: UUID) {
        let task = session.uploadTask(with: request, fromFile: fileURL)
        task.taskDescription = noteID.uuidString
        task.resume()
    }

    /// Note IDs with an upload still owned by the system.
    func runningNoteIDs() async -> Set<UUID> {
        let tasks = await session.allTasks
        return Set(tasks.compactMap { task in
            guard task.state == .running || task.state == .suspended else { return nil }
            return Self.noteID(task.taskDescription)
        })
    }

    /// For the urlSession background task: wait until the system has handed
    /// over every event for this session, or the time is up.
    func waitForEvents(timeout: TimeInterval = 20) async {
        _ = session // Touching the session reconnects it to the system's queue
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if takeFinishedEvents() { break }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        // Let the main actor apply the last results before the app suspends
        try? await Task.sleep(nanoseconds: 300_000_000)
    }

    private func takeFinishedEvents() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let finished = finishedEvents
        finishedEvents = false
        return finished
    }

    /// Tasks started by an older build carry "<note id>|<token ref>".
    private static func noteID(_ description: String?) -> UUID? {
        guard let description else { return nil }
        return description.split(separator: "|", maxSplits: 1).first.flatMap { UUID(uuidString: String($0)) }
    }

    /// The bearer token the request was sent with.
    private static func token(of task: URLSessionTask) -> String? {
        guard let header = task.originalRequest?.value(forHTTPHeaderField: "Authorization") else { return nil }
        return header.hasPrefix("Bearer ") ? String(header.dropFirst("Bearer ".count)) : header
    }

    // MARK: - URLSessionDataDelegate

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        buffers[dataTask.taskIdentifier, default: Data()].append(data)
        lock.unlock()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        let body = buffers.removeValue(forKey: task.taskIdentifier) ?? Data()
        lock.unlock()

        guard let noteID = Self.noteID(task.taskDescription) else { return }
        let response = task.response as? HTTPURLResponse
        let outcome = RelayUploadOutcome(
            noteID: noteID,
            token: Self.token(of: task),
            status: error == nil ? response?.statusCode : nil,
            body: body,
            retryAfter: (response?.value(forHTTPHeaderField: "Retry-After")).flatMap { TimeInterval($0.trimmingCharacters(in: .whitespaces)) },
            errorDescription: error.map { String(describing: $0) }
        )
        Task { @MainActor in
            WatchRelayService.shared.handleUpload(outcome)
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        lock.lock()
        finishedEvents = true
        lock.unlock()
    }
}
