//
//  RelayService.swift
//  Ramble
//
//  HTTP client for the Ramble Relay (relay/ in this repo). The relay holds
//  transcripts until the user's agent pulls and acknowledges them.
//
//  Two credentials:
//  - The inbox secret (rmbi_…) is this phone's credential. Created once,
//    kept in the Keychain, never shown to the user.
//  - Agent tokens (rmba_…) belong to the agents. The app never sees them;
//    it only hands out short pairing codes the agent exchanges for one.
//

import Foundation

enum RelayAgent: String, CaseIterable, Identifiable, Codable {
    case muse
    case chatgpt
    case claude
    case grok
    case other

    var id: String { rawValue }

    /// Agents offered in the Connect agent picker. MVP is Muse only; the
    /// relay already accepts the other types, so adding one is a one-line
    /// change here plus its setup copy. Grok is next, once the relay's push
    /// path (`/forward`) exists — Grok takes webhooks, it doesn't poll.
    static let pickable: [RelayAgent] = [.muse]

    var displayName: String {
        switch self {
        case .muse: return "Muse"
        case .chatgpt: return "ChatGPT"
        case .claude: return "Claude"
        case .grok: return "Grok"
        case .other: return "Another agent"
        }
    }

    var iconName: String {
        switch self {
        case .muse: return "sparkle"
        case .chatgpt: return "bubble.left.and.text.bubble.right"
        case .claude: return "asterisk"
        case .grok: return "bolt"
        case .other: return "terminal"
        }
    }
}

struct RelayPairCode: Decodable {
    let code: String
    let agentType: RelayAgent
    let expiresAt: Date
}

struct RelayConnection: Decodable, Identifiable, Hashable {
    let id: String
    let agentType: RelayAgent
    let createdAt: Date
    let lastPullAt: Date?
    let pending: Int
}

enum RelayError: LocalizedError {
    case notConfigured
    case attestationUnavailable
    case unauthorized
    case server(status: Int, message: String?)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "The Ramble relay isn't set up in this build yet."
        case .attestationUnavailable:
            return "Couldn't verify this device with Apple. Try again in a moment."
        case .unauthorized:
            return "This phone's relay inbox wasn't recognized."
        case .server(let status, let message):
            return message ?? "The relay returned an error (\(status))."
        case .network(let detail):
            return detail
        }
    }

    /// Worth retrying later without any change on the user's side.
    var isTransient: Bool {
        switch self {
        case .network, .attestationUnavailable: return true
        case .server(let status, _): return status >= 500 || status == 429
        case .notConfigured, .unauthorized: return false
        }
    }
}

@MainActor
final class RelayService: ObservableObject {
    static let shared = RelayService()

    private static let inboxSecretKey = "relayInboxSecret"
    private static let connectionCountKey = "relayConnectionCount"

    /// Last known connections, for Settings. Refreshed by `refreshConnections()`.
    @Published private(set) var connections: [RelayConnection] = []

    private let appAttest = AppAttestService.shared
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            // The relay sends JavaScript's toISOString(), which has milliseconds.
            let string = try decoder.singleValueContainer().decode(String.self)
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: string) ?? ISO8601DateFormatter().date(from: string) {
                return date
            }
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath, debugDescription: "Bad date \(string)"
            ))
        }
        return decoder
    }()

    private static let iso = ISO8601DateFormatter()

    private init() {}

    // MARK: - State

    var isConfigured: Bool { Constants.Relay.baseURL != nil }

    var hasInbox: Bool { KeychainService.string(forKey: Self.inboxSecretKey) != nil }

    /// Whether new transcripts should go to the relay. Cached so the upload
    /// queue doesn't need a network call to decide; refreshed whenever the
    /// connection list is loaded or changed.
    var hasConnectedAgents: Bool {
        isConfigured && hasInbox && UserDefaults.standard.integer(forKey: Self.connectionCountKey) > 0
    }

    /// Name to show for "Waiting for …" copy. The connected agent's name when
    /// every connection is the same kind; Muse otherwise (the MVP agent).
    var primaryAgentName: String {
        let types = Set(connections.map(\.agentType))
        if types.count == 1, let only = types.first { return only.displayName }
        return RelayAgent.muse.displayName
    }

    // MARK: - App-facing calls

    /// Issues a single-use pairing code for one agent, creating this phone's
    /// inbox first if needed.
    func createPairCode(for agent: RelayAgent) async throws -> RelayPairCode {
        let body = try JSONSerialization.data(withJSONObject: ["agent_type": agent.rawValue])
        let data = try await send("POST", "pair/code", body: body, auth: try await ensureInbox())
        return try decoder.decode(RelayPairCode.self, from: data)
    }

    @discardableResult
    func refreshConnections() async throws -> [RelayConnection] {
        guard hasInbox else {
            setConnections([])
            return []
        }
        let data = try await send("GET", "connections", auth: try await ensureInbox())
        let list = try decoder.decode(ConnectionList.self, from: data).connections
        setConnections(list)
        return list
    }

    /// Disconnect: kills the agent's token on the relay and deletes its queue.
    func disconnect(_ connection: RelayConnection) async throws {
        do {
            _ = try await send("DELETE", "connections/\(connection.id)", auth: try await ensureInbox())
        } catch RelayError.server(status: 404, _) {
            // Already gone — that's the outcome the user wanted.
        }
        setConnections(connections.filter { $0.id != connection.id })
    }

    /// Delete everything now: empties every agent's queue on the relay.
    /// Connections stay; nothing waiting is delivered.
    func deleteAllQueued() async throws -> Int {
        guard hasInbox else { return 0 }
        let data = try await send("DELETE", "inbox", auth: try await ensureInbox())
        let result = try decoder.decode(DeletedCount.self, from: data)
        try? await refreshConnections()
        return result.deleted
    }

    /// Uploads one transcript. Returns how many agents it was queued for.
    func upload(recording: Recording, transcription: String) async throws -> Int {
        let payload: [String: Any] = [
            "recording_id": recording.id.uuidString,
            "created_at": Self.iso.string(from: recording.createdAt),
            "duration": recording.duration,
            "transcription": transcription,
        ]
        let body = try JSONSerialization.data(withJSONObject: payload)
        // No attestation here: the device proved itself once when the inbox
        // was created, and delivery shouldn't hinge on attestation working.
        let data = try await send("POST", "inbox", body: body, auth: try await ensureInbox())
        return try decoder.decode(UploadResult.self, from: data).queued
    }

    // MARK: - Inbox

    private func ensureInbox() async throws -> String {
        if let secret = KeychainService.string(forKey: Self.inboxSecretKey) {
            return secret
        }
        let data = try await send("POST", "inboxes", body: Data(), attest: true)
        let created = try decoder.decode(CreatedInbox.self, from: data)
        KeychainService.setString(created.inboxSecret, forKey: Self.inboxSecretKey)
        return created.inboxSecret
    }

    private func setConnections(_ list: [RelayConnection]) {
        connections = list
        UserDefaults.standard.set(list.count, forKey: Self.connectionCountKey)
    }

    // MARK: - Transport

    private func send(
        _ method: String,
        _ path: String,
        body: Data? = nil,
        auth: String? = nil,
        attest: Bool = false
    ) async throws -> Data {
        guard let baseURL = Constants.Relay.baseURL else { throw RelayError.notConfigured }

        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.timeoutInterval = 15
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let auth {
            request.setValue("Bearer \(auth)", forHTTPHeaderField: "Authorization")
        }
        if attest {
            try await addAttestation(to: &request, body: body ?? Data(), baseURL: baseURL)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw RelayError.network(Self.describe(error))
        }

        guard let http = response as? HTTPURLResponse else {
            throw RelayError.network("Invalid response")
        }
        switch http.statusCode {
        case 200...299:
            return data
        case 401:
            // The relay doesn't know this inbox (e.g. a self-hosted relay was
            // reset). Forget it so the next call starts fresh.
            if auth?.hasPrefix("rmbi_") == true {
                KeychainService.delete(forKey: Self.inboxSecretKey)
                setConnections([])
            }
            throw RelayError.unauthorized
        case 403 where attest:
            throw RelayError.attestationUnavailable
        default:
            let message = (try? decoder.decode(ErrorBody.self, from: data))?.error
            throw RelayError.server(status: http.statusCode, message: message)
        }
    }

    private func addAttestation(to request: inout URLRequest, body: Data, baseURL: URL) async throws {
        // Simulator / local relay: same developer override the proxy uses.
        if let bypass = UserDefaults.standard.string(forKey: SubscriptionService.devOverrideUserDefaultsKey),
           !bypass.isEmpty {
            request.setValue(bypass, forHTTPHeaderField: "X-Dev-Bypass")
            return
        }

        try? await appAttest.attestIfNeeded(server: baseURL)
        guard let assertion = await appAttest.generateAssertion(for: body) else {
            throw RelayError.attestationUnavailable
        }
        request.setValue(assertion.keyId, forHTTPHeaderField: "X-App-Attest-Key-Id")
        request.setValue(assertion.assertion.base64EncodedString(), forHTTPHeaderField: "X-App-Attest")
    }

    private static func describe(_ error: Error) -> String {
        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else { return "Request failed" }
        switch nsError.code {
        case NSURLErrorTimedOut: return "Request timed out"
        case NSURLErrorNotConnectedToInternet: return "No internet connection"
        case NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost: return "Can't reach the relay"
        default: return "Network error (code \(nsError.code))"
        }
    }
}

// MARK: - Wire types

private struct CreatedInbox: Decodable {
    let inboxId: String
    let inboxSecret: String
}

private struct ConnectionList: Decodable {
    let connections: [RelayConnection]
}

private struct UploadResult: Decodable {
    let queued: Int
}

private struct DeletedCount: Decodable {
    let deleted: Int
}

private struct ErrorBody: Decodable {
    let error: String
}
