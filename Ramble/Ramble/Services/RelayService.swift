//
//  RelayService.swift
//  Ramble
//
//  Client for Ramble's relay (specs/relay-api.md). This phone's credential
//  is an inbox secret kept in the Keychain. The watch gets its own scoped
//  token from here; agents get theirs by exchanging a pairing code, so the
//  app never sees them.
//

import Combine
import Foundation

struct RelayPairCode: Decodable {
    let code: String
    let expiresAt: Date
}

struct RelayConnection: Decodable, Identifiable, Hashable {
    let id: String
    /// What the agent called itself when it paired ("Grok Bot"). Optional.
    let name: String?
    let createdAt: Date
    let lastPullAt: Date?
    let pending: Int
    /// Set when the agent registered a wake-up webhook with the relay.
    let hook: RelayHook?
}

/// An agent's wake-up webhook, as the relay reports it. The URL and headers
/// stay on the relay; the app only sees whether the last ping worked.
struct RelayHook: Decodable, Hashable {
    let lastPingAt: Date?
    /// HTTP status of the last ping; 0 means no response.
    let lastStatus: Int?

    var isFailing: Bool {
        guard let lastStatus else { return false }
        return !(200..<300).contains(lastStatus)
    }
}

/// A note as the relay returns it ("The note shape").
struct RelayNote: Decodable {
    let id: String
    let source: String
    let status: String
    let result: String?
    /// Exactly as the device sent it, offset included.
    let recordedAt: String
    let receivedAt: Date?
    let duration: Double?
    let transcript: String?
    let transcriptCleared: Bool?

    var uuid: UUID? { UUID(uuidString: id) }
}

/// Per-note agent delivery (POST /inbox/status).
struct RelayDeliveryStatus: Decodable {
    let recordingId: String
    let copies: Int
    let waiting: Int
    let pickedUp: Int
    let removed: Int
    let firstPickedUpAt: Date?
    /// One per copy; nil from a relay that only sends the counts.
    let agents: [RelayAgentCopy]?
}

/// One agent's copy of a note, as POST /inbox/status reports it.
struct RelayAgentCopy: Decodable {
    let connectionId: String
    let name: String?
    /// "waiting", "picked_up" or "removed".
    let state: String
    let pickedUpAt: Date?
}

/// Transcription options kept with the inbox (GET/PUT /settings).
struct RelayTranscriptionSettings: Codable, Equatable {
    var language: String?
    var removeFillerWords: Bool
    var vocabulary: String
}

enum RelayError: LocalizedError {
    case attestationUnavailable
    /// The inbox secret can't be read until the phone is unlocked.
    case deviceLocked
    /// The person hasn't tapped "Get started" on this install yet.
    case notConsented
    case unauthorized
    case server(status: Int, message: String?, reason: String? = nil)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .attestationUnavailable: return "Couldn't verify this device with Apple. Try again in a moment."
        case .deviceLocked: return "Waiting for this \(ThisDevice.name) to be unlocked."
        case .notConsented: return "Ramble isn't set up yet."
        case .unauthorized: return "Ramble's server didn't recognize this \(ThisDevice.name). Try again."
        case .server(let status, let message, _): return message ?? "Ramble's server returned an error (\(status))."
        case .network(let detail): return detail
        }
    }

    /// The relay's `"reason"` code, when it sent one.
    var reason: String? {
        if case .server(_, _, let reason) = self { return reason }
        return nil
    }

    var status: Int? {
        if case .server(let status, _, _) = self { return status }
        return nil
    }

    /// Worth retrying later without any change on the user's side.
    var isTransient: Bool {
        switch self {
        case .network, .attestationUnavailable, .deviceLocked, .notConsented: return true
        case .server(let status, _, _): return status >= 500 || status == 429
        case .unauthorized: return false
        }
    }
}

@MainActor
final class RelayService: ObservableObject {
    static let shared = RelayService()

    private static let inboxSecretKey = "relayInboxSecret"
    private static let connectionCountKey = "relayConnectionCount"
    private static let connectedSinceKey = "relayConnectedSince"

    @Published private(set) var connections: [RelayConnection] = []
    /// Setting up with the server failed for a reason the person can't fix
    /// (offline, or the server refusing new setups). Retried on each open.
    @Published private(set) var setupProblem = false

    let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let string = try decoder.singleValueContainer().decode(String.self)
            guard let date = RelayService.parseDate(string) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: string))
            }
            return date
        }
        return decoder
    }()

    /// ISO 8601 with or without milliseconds (the relay sends toISOString(),
    /// devices send seconds with an offset).
    nonisolated static func parseDate(_ string: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: string) { return date }
        return ISO8601DateFormatter().date(from: string)
    }

    /// App build and OS for X-Ramble-Client ("Ramble/1.3 (142) iOS/26.2"),
    /// kept by the relay for usage stats and debugging (specs/relay-api.md).
    nonisolated static let clientLabel: String = {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return "Ramble/\(version) (\(build)) iOS/\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
    }()

    /// When recording started, in the phone's own offset
    /// (2026-11-01T07:59:00-05:00), for X-Ramble-Recorded-At.
    nonisolated static func localTimestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = .current
        return formatter.string(from: date)
    }

    private init() {}

    /// True while the phone is locked too: the secret is there, just unreadable.
    var hasInbox: Bool { KeychainService.lookup(forKey: Self.inboxSecretKey) != .notFound }

    /// Whether any agent is connected, cached from the last connections
    /// refresh so it's readable without a network call or while locked.
    var hasConnectedAgents: Bool {
        hasInbox && UserDefaults.standard.integer(forKey: Self.connectionCountKey) > 0
    }

    /// When the longest-connected agent was paired, from the last refresh.
    var connectedSince: Date? {
        UserDefaults.standard.object(forKey: Self.connectedSinceKey) as? Date
    }

    // MARK: - Setup

    /// Creates the inbox if this install has none. Only after consent.
    func setUpIfNeeded() async {
        guard Consent.hasConsented, !KeychainService.isLocked else { return }
        _ = try? await ensureInbox()
    }

    // MARK: - Agents

    func createPairCode() async throws -> RelayPairCode {
        let data = try await send("POST", "pair/code", auth: try await ensureInbox())
        return try decoder.decode(RelayPairCode.self, from: data)
    }

    @discardableResult
    func refreshConnections() async throws -> [RelayConnection] {
        guard hasInbox else { return [] }
        let data = try await send("GET", "connections", auth: try await ensureInbox())
        let list = try decoder.decode(ConnectionList.self, from: data).connections
        setConnections(list)
        return list
    }

    /// Kills the agent's key and deletes whatever was waiting for it.
    func disconnect(_ connection: RelayConnection) async throws {
        do {
            _ = try await send("DELETE", "connections/\(connection.id)", auth: try await ensureInbox())
        } catch RelayError.server(status: 404, _, _) {
            // Already gone.
        }
        setConnections(connections.filter { $0.id != connection.id })
    }

    /// Deletes every agent copy still waiting. Agents stay connected.
    func deleteAllWaiting() async throws -> Int {
        guard hasInbox else { return 0 }
        let data = try await send("DELETE", "inbox", auth: try await ensureInbox())
        try? await refreshConnections()
        return try decoder.decode(DeletedCount.self, from: data).deleted
    }

    // MARK: - Account

    func fetchAccount() async throws -> RelayAccount {
        let data = try await send("GET", "account", auth: try await ensureInbox())
        return try decoder.decode(RelayAccount.self, from: data)
    }

    func submitEntitlement(_ body: [String: String]) async throws -> RelayAccount {
        let payload = try JSONSerialization.data(withJSONObject: body)
        let data = try await send("POST", "entitlement", body: payload, auth: try await ensureInbox())
        return try decoder.decode(RelayAccount.self, from: data)
    }

    // MARK: - Transcription settings

    func fetchTranscriptionSettings() async throws -> RelayTranscriptionSettings {
        let data = try await send("GET", "settings", auth: try await ensureInbox())
        return try decoder.decode(RelayTranscriptionSettings.self, from: data)
    }

    @discardableResult
    func saveTranscriptionSettings(_ settings: RelayTranscriptionSettings) async throws -> RelayTranscriptionSettings {
        let body = try JSONSerialization.data(withJSONObject: [
            "language": settings.language.map { $0 as Any } ?? NSNull(),
            "remove_filler_words": settings.removeFillerWords,
            "vocabulary": settings.vocabulary,
        ])
        let data = try await send("PUT", "settings", body: body, auth: try await ensureInbox())
        return try decoder.decode(RelayTranscriptionSettings.self, from: data)
    }

    // MARK: - Watch token

    /// A fresh watch token, replacing `replaces` and any other of this inbox.
    func mintWatchToken(replaces: String?) async throws -> String {
        var payload: [String: Any] = [:]
        if let replaces, !replaces.isEmpty { payload["replaces"] = replaces }
        let body = try JSONSerialization.data(withJSONObject: payload)
        let data = try await send("POST", "watch-token", body: body, auth: try await ensureInbox())
        return try decoder.decode(WatchToken.self, from: data).watchToken
    }

    // MARK: - Notes

    /// One page of notes the phone hasn't acked, oldest accepted first.
    func listNotes(after cursor: String?) async throws -> (notes: [RelayNote], next: String?) {
        var path = "notes"
        if let cursor, let escaped = cursor.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            path += "?after=\(escaped)"
        }
        let data = try await send("GET", path, auth: try await ensureInbox())
        let page = try decoder.decode(NotePage.self, from: data)
        return (page.notes, page.next)
    }

    /// Acks saved notes. Returns the IDs the relay says are still transcribing.
    @discardableResult
    func ackNotes(_ ids: [UUID]) async throws -> [String] {
        guard !ids.isEmpty else { return [] }
        var notFinal: [String] = []
        for start in stride(from: 0, to: ids.count, by: 500) {
            let batch = ids[start..<min(start + 500, ids.count)].map(\.uuidString)
            let body = try JSONSerialization.data(withJSONObject: ["ids": batch])
            let data = try await send("POST", "notes/ack", body: body, auth: try await ensureInbox())
            notFinal += (try? decoder.decode(AckResult.self, from: data).notFinal) ?? []
        }
        return notFinal
    }

    /// Agent delivery for up to 100 notes per call. Notes the relay no longer
    /// knows are left out of the result.
    func deliveryStatus(for ids: [UUID]) async throws -> [UUID: RelayDeliveryStatus] {
        guard hasInbox, !ids.isEmpty else { return [:] }
        var result: [UUID: RelayDeliveryStatus] = [:]
        for start in stride(from: 0, to: ids.count, by: 100) {
            let batch = ids[start..<min(start + 100, ids.count)].map(\.uuidString)
            let body = try JSONSerialization.data(withJSONObject: ["recording_ids": batch])
            let data = try await send("POST", "inbox/status", body: body, auth: try await ensureInbox())
            for item in try decoder.decode(StatusList.self, from: data).recordings {
                if let id = UUID(uuidString: item.recordingId) { result[id] = item }
            }
        }
        return result
    }

    /// The raw outcome of `PUT /notes/:id`, for the upload queue to sort out.
    struct UploadResponse {
        let status: Int
        let note: RelayNote?
        let reason: String?
        let message: String?
        let retryAfter: TimeInterval?
    }

    /// Uploads a note's audio. Throws only when no HTTP response came back
    /// (or the phone can't authenticate yet).
    func uploadNote(_ recording: Recording, isRetry: Bool) async throws -> UploadResponse {
        let secret = try await ensureInbox()
        let fileURL = recording.audioFileURL
        let size = ((try? FileManager.default.attributesOfItem(atPath: fileURL.path))?[.size] as? NSNumber)?.intValue ?? 0

        var request = URLRequest(url: Constants.Relay.baseURL.appendingPathComponent("notes/\(recording.id.uuidString)"))
        request.httpMethod = "PUT"
        // The relay answers once the audio is stored, then waits up to 8 s
        // for the transcript; a 60-minute note takes a while to send.
        request.timeoutInterval = 120
        request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        request.setValue("audio/mp4", forHTTPHeaderField: "Content-Type")
        request.setValue("\(size)", forHTTPHeaderField: "Content-Length")
        request.setValue(Self.localTimestamp(recording.createdAt), forHTTPHeaderField: "X-Ramble-Recorded-At")
        if isRetry { request.setValue("1", forHTTPHeaderField: "X-Ramble-Retry") }
        request.setValue(Self.clientLabel, forHTTPHeaderField: "X-Ramble-Client")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.upload(for: request, fromFile: fileURL)
        } catch {
            throw RelayError.network(Self.describe(error))
        }
        let http = response as? HTTPURLResponse
        let status = http?.statusCode ?? 0
        if status == 401 { forgetInbox() }
        let body = try? decoder.decode(ErrorBody.self, from: data)
        let retryAfter = http?.value(forHTTPHeaderField: "Retry-After").flatMap { TimeInterval($0) }
        let note = (200...299).contains(status) ? try? decoder.decode(RelayNote.self, from: data) : nil
        return UploadResponse(status: status, note: note, reason: body?.reason, message: body?.error, retryAfter: retryAfter)
    }

    // MARK: - Inbox

    /// App Attest is checked only here, once per install.
    private func ensureInbox() async throws -> String {
        switch KeychainService.lookup(forKey: Self.inboxSecretKey) {
        case .found(let secret): return secret
        // Never mint a new inbox here: the real one would be orphaned along
        // with every agent paired to it.
        case .locked: throw RelayError.deviceLocked
        case .notFound: break
        }
        guard Consent.hasConsented else { throw RelayError.notConsented }
        // Creating an inbox needs App Attest, whose key is locked too.
        guard !KeychainService.isLocked else { throw RelayError.deviceLocked }

        // One creation at a time: several callers wake up together at launch.
        if let inboxTask { return try await inboxTask.value }
        let task = Task { try await self.createInbox() }
        inboxTask = task
        defer { inboxTask = nil }
        return try await task.value
    }

    private var inboxTask: Task<String, Error>?

    private func createInbox() async throws -> String {
        // Empty body: the assertion covers it. A buyer's purchase is sent
        // afterwards with POST /entitlement (PurchaseService).
        let body = Data()

        var headers: [String: String] = [:]
        let bypass = Constants.Relay.devBypass
        if !bypass.isEmpty {
            headers["X-Dev-Bypass"] = bypass // Debug builds against a local relay only
        } else {
            do {
                try await AppAttestService.shared.attestIfNeeded(server: Constants.Relay.baseURL)
            } catch {
                setupProblem = true
                throw RelayError.attestationUnavailable
            }
            guard let assertion = await AppAttestService.shared.generateAssertion(for: body) else {
                setupProblem = true
                throw RelayError.attestationUnavailable
            }
            headers["X-App-Attest-Key-Id"] = assertion.keyId
            headers["X-App-Attest"] = assertion.assertion.base64EncodedString()
        }

        let data: Data
        do {
            data = try await send("POST", "inboxes", headers: headers)
        } catch {
            setupProblem = true
            if (error as? RelayError)?.status == 403 { throw RelayError.attestationUnavailable }
            throw error
        }
        let created = try decoder.decode(CreatedInbox.self, from: data)
        KeychainService.setString(created.inboxSecret, forKey: Self.inboxSecretKey)
        setupProblem = false
        // A new account: the refresh below fills in the real state, and the
        // account change sends any purchase on this Apple ID.
        PurchaseService.shared.inboxCreated()
        AccountService.shared.apply(RelayAccount(
            unlocked: false,
            freeNotesTotal: 25,
            freeNotesRemaining: 25
        ))
        // A fresh inbox needs a fresh watch connection, and the real account state.
        Task {
            await PhoneConnectivityService.shared.connectWatch(force: true, replaces: nil)
            await AccountService.shared.refresh()
        }
        return created.inboxSecret
    }

    /// The relay doesn't know this inbox. Forget it so the next call starts fresh.
    private func forgetInbox() {
        KeychainService.delete(forKey: Self.inboxSecretKey)
        setConnections([])
    }

    private func setConnections(_ list: [RelayConnection]) {
        connections = list
        UserDefaults.standard.set(list.count, forKey: Self.connectionCountKey)
        UserDefaults.standard.set(list.map(\.createdAt).min(), forKey: Self.connectedSinceKey)
    }

    // MARK: - Transport

    private func send(
        _ method: String,
        _ path: String,
        body: Data? = nil,
        auth: String? = nil,
        headers: [String: String] = [:]
    ) async throws -> Data {
        // appendingPathComponent would escape a query string.
        guard let url = URL(string: path, relativeTo: Self.baseWithSlash) else {
            throw RelayError.network("Bad address")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30
        request.httpBody = body
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if let auth { request.setValue("Bearer \(auth)", forHTTPHeaderField: "Authorization") }
        request.setValue(Self.clientLabel, forHTTPHeaderField: "X-Ramble-Client")
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw RelayError.network(Self.describe(error))
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0

        if (200...299).contains(status) { return data }
        if status == 401 {
            forgetInbox()
            throw RelayError.unauthorized
        }
        let errorBody = try? decoder.decode(ErrorBody.self, from: data)
        throw RelayError.server(status: status, message: errorBody?.error, reason: errorBody?.reason)
    }

    private static var baseWithSlash: URL {
        let base = Constants.Relay.baseURL.absoluteString
        return URL(string: base.hasSuffix("/") ? base : base + "/") ?? Constants.Relay.baseURL
    }

    nonisolated static func describe(_ error: Error) -> String {
        let code = (error as NSError).code
        if code == NSURLErrorNotConnectedToInternet { return "No internet connection." }
        if code == NSURLErrorTimedOut { return "The connection timed out." }
        return "Can't reach Ramble's server."
    }
}

private struct CreatedInbox: Decodable {
    let inboxSecret: String
}
private struct ConnectionList: Decodable { let connections: [RelayConnection] }
private struct DeletedCount: Decodable { let deleted: Int }
private struct WatchToken: Decodable { let watchToken: String }
private struct NotePage: Decodable {
    let notes: [RelayNote]
    let next: String?
}
private struct AckResult: Decodable { let notFinal: [String]? }
private struct StatusList: Decodable { let recordings: [RelayDeliveryStatus] }
private struct ErrorBody: Decodable {
    let error: String?
    let reason: String?
}

/// Tapping "Get started" is the person's consent to cloud transcription
/// (specs/phone.md). Nothing uploads, and the watch isn't connected, before.
/// Installs that finished onboarding in an earlier, on-device build never
/// saw the consent line, so they consent on a one-time notice instead
/// (ConsentNoticeView).
enum Consent {
    static let key = "hasConsentedToCloudTranscription"

    static var hasConsented: Bool {
        UserDefaults.standard.bool(forKey: key)
    }

    /// Records consent, then sets up with the server, connects the watch
    /// and uploads whatever was waiting.
    @MainActor
    static func give() {
        UserDefaults.standard.set(true, forKey: key)
        Task { @MainActor in
            // A new inbox connects the watch itself; a kept one (reinstall)
            // still gives the watch a fresh token.
            let hadInbox = RelayService.shared.hasInbox
            await RelayService.shared.setUpIfNeeded()
            if hadInbox {
                await PhoneConnectivityService.shared.connectWatch(force: true, replaces: nil)
            }
            BackgroundTaskService.shared.appDidOpen()
        }
    }
}
