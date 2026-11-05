//
//  RelayService.swift
//  Ramble
//
//  Client for the Ramble Relay (proxy/RELAY.md), which holds transcripts until
//  the user's agent picks them up. This phone's credential is an inbox secret
//  kept in the Keychain. Agents get their own tokens by exchanging a pairing
//  code, so the app never sees them.
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

enum RelayError: LocalizedError {
    case attestationUnavailable
    /// The inbox secret can't be read until the phone is unlocked.
    case deviceLocked
    case unauthorized
    case server(status: Int, message: String?)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .attestationUnavailable: return "Couldn't verify this device with Apple. Try again in a moment."
        case .deviceLocked: return "Waiting for this iPhone to be unlocked."
        case .unauthorized: return "The relay didn't recognize this phone. Try again."
        case .server(let status, let message): return message ?? "The relay returned an error (\(status))."
        case .network(let detail): return detail
        }
    }

    /// Worth retrying later without any change on the user's side.
    var isTransient: Bool {
        switch self {
        case .network, .attestationUnavailable, .deviceLocked: return true
        case .server(let status, _): return status >= 500 || status == 429
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

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            // The relay sends JavaScript's toISOString(), which has milliseconds.
            let string = try decoder.singleValueContainer().decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            guard let date = formatter.date(from: string) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: string))
            }
            return date
        }
        return decoder
    }()

    private init() {}

    /// True while the phone is locked too: the secret is there, just unreadable.
    var hasInbox: Bool { KeychainService.lookup(forKey: Self.inboxSecretKey) != .notFound }

    /// Whether new transcripts should go to the relay. Cached so the upload
    /// queue can decide without a network call, and readable while locked.
    var hasConnectedAgents: Bool {
        hasInbox && UserDefaults.standard.integer(forKey: Self.connectionCountKey) > 0
    }

    /// When the longest-connected agent was paired, cached from the last
    /// connections refresh. Recordings made since then should reach an agent.
    var connectedSince: Date? {
        UserDefaults.standard.object(forKey: Self.connectedSinceKey) as? Date
    }

    // MARK: - Calls

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

    /// Kills the agent's token and deletes whatever was waiting for it.
    func disconnect(_ connection: RelayConnection) async throws {
        do {
            _ = try await send("DELETE", "connections/\(connection.id)", auth: try await ensureInbox())
        } catch RelayError.server(status: 404, _) {
            // Already gone.
        }
        setConnections(connections.filter { $0.id != connection.id })
    }

    /// Deletes everything waiting on the relay. Agents stay connected.
    func deleteAllWaiting() async throws -> Int {
        guard hasInbox else { return 0 }
        let data = try await send("DELETE", "inbox", auth: try await ensureInbox())
        try? await refreshConnections()
        return try decoder.decode(DeletedCount.self, from: data).deleted
    }

    private static let localTimestamp: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = .current
        return formatter
    }()

    /// Returns how many agents it was queued for.
    func upload(recording: Recording, transcription: String) async throws -> Int {
        let body = try JSONSerialization.data(withJSONObject: [
            "recording_id": recording.id.uuidString,
            // When recording started, in the phone's local offset (like
            // 2026-11-01T07:59:00-05:00), so the agent can read "tomorrow at 9"
            // in the user's own time.
            "created_at": Self.localTimestamp.string(from: recording.createdAt),
            "duration": recording.duration,
            "transcription": transcription,
        ])
        let data = try await send("POST", "inbox", body: body, auth: try await ensureInbox())
        return try decoder.decode(UploadResult.self, from: data).queued
    }

    /// How many agents each recording is still waiting for on the relay.
    /// 0 means every agent picked it up (or it expired).
    func waitingCounts(for recordingIds: [UUID]) async throws -> [UUID: Int] {
        guard hasInbox, !recordingIds.isEmpty else { return [:] }
        let body = try JSONSerialization.data(withJSONObject: [
            "recording_ids": recordingIds.map(\.uuidString),
        ])
        let data = try await send("POST", "inbox/status", body: body, auth: try await ensureInbox())
        var counts: [UUID: Int] = [:]
        for item in try decoder.decode(StatusList.self, from: data).recordings {
            if let id = UUID(uuidString: item.recordingId) { counts[id] = item.waiting }
        }
        return counts
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
        // Creating an inbox needs App Attest, whose key is locked too.
        guard !KeychainService.isLocked else { throw RelayError.deviceLocked }

        var headers: [String: String] = [:]
        if let bypass = UserDefaults.standard.string(forKey: SubscriptionService.devOverrideUserDefaultsKey),
           !bypass.isEmpty {
            headers["X-Dev-Bypass"] = bypass // Simulator / local relay
        } else {
            try? await AppAttestService.shared.attestIfNeeded(server: Constants.Relay.baseURL)
            guard let assertion = await AppAttestService.shared.generateAssertion(for: Data()) else {
                throw RelayError.attestationUnavailable
            }
            headers["X-App-Attest-Key-Id"] = assertion.keyId
            headers["X-App-Attest"] = assertion.assertion.base64EncodedString()
        }

        let data: Data
        do {
            data = try await send("POST", "inboxes", headers: headers)
        } catch RelayError.server(status: 403, _) {
            throw RelayError.attestationUnavailable
        }
        let secret = try decoder.decode(CreatedInbox.self, from: data).inboxSecret
        KeychainService.setString(secret, forKey: Self.inboxSecretKey)
        return secret
    }

    /// The relay just said no agent is connected. Believe it right away so a
    /// failed refresh can't leave a stale count that keeps re-sending.
    func noteNoAgentsConnected() {
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
        var request = URLRequest(url: Constants.Relay.baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.timeoutInterval = 15
        request.httpBody = body
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if let auth { request.setValue("Bearer \(auth)", forHTTPHeaderField: "Authorization") }
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw RelayError.network((error as NSError).code == NSURLErrorNotConnectedToInternet
                ? "No internet connection" : "Can't reach the relay")
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0

        if (200...299).contains(status) { return data }
        if status == 401 {
            // The relay doesn't know this inbox. Forget it so the next call starts fresh.
            KeychainService.delete(forKey: Self.inboxSecretKey)
            setConnections([])
            throw RelayError.unauthorized
        }
        throw RelayError.server(status: status, message: (try? decoder.decode(ErrorBody.self, from: data))?.error)
    }
}

private struct CreatedInbox: Decodable { let inboxSecret: String }
private struct ConnectionList: Decodable { let connections: [RelayConnection] }
private struct UploadResult: Decodable { let queued: Int }
private struct DeletedCount: Decodable { let deleted: Int }
private struct StatusList: Decodable {
    struct Item: Decodable { let recordingId: String; let waiting: Int }
    let recordings: [Item]
}
private struct ErrorBody: Decodable { let error: String }
