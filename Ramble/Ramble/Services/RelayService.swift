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
    let createdAt: Date
    let lastPullAt: Date?
    let pending: Int
}

enum RelayError: LocalizedError {
    case attestationUnavailable
    case unauthorized
    case server(status: Int, message: String?)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .attestationUnavailable: return "Couldn't verify this device with Apple. Try again in a moment."
        case .unauthorized: return "The relay didn't recognize this phone. Try again."
        case .server(let status, let message): return message ?? "The relay returned an error (\(status))."
        case .network(let detail): return detail
        }
    }

    /// Worth retrying later without any change on the user's side.
    var isTransient: Bool {
        switch self {
        case .network, .attestationUnavailable: return true
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

    var hasInbox: Bool { KeychainService.string(forKey: Self.inboxSecretKey) != nil }

    /// Whether new transcripts should go to the relay. Cached so the upload
    /// queue can decide without a network call.
    var hasConnectedAgents: Bool {
        hasInbox && UserDefaults.standard.integer(forKey: Self.connectionCountKey) > 0
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

    /// Returns how many agents it was queued for.
    func upload(recording: Recording, transcription: String) async throws -> Int {
        let body = try JSONSerialization.data(withJSONObject: [
            "recording_id": recording.id.uuidString,
            "created_at": ISO8601DateFormatter().string(from: recording.createdAt),
            "duration": recording.duration,
            "transcription": transcription,
        ])
        let data = try await send("POST", "inbox", body: body, auth: try await ensureInbox())
        return try decoder.decode(UploadResult.self, from: data).queued
    }

    // MARK: - Inbox

    /// App Attest is checked only here, once per install.
    private func ensureInbox() async throws -> String {
        if let secret = KeychainService.string(forKey: Self.inboxSecretKey) { return secret }

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
private struct ErrorBody: Decodable { let error: String }
