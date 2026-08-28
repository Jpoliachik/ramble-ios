//
//  AppAttestService.swift
//  Ramble
//

import CryptoKit
import DeviceCheck
import Foundation

final class AppAttestService {
    static let shared = AppAttestService()

    private static let keyIdKey = "appAttestKeyId"
    private static let isAttestedKey = "appAttestIsAttested"

    private let settingsService = SettingsService.shared

    private init() {}

    // MARK: - Public State

    var isSupported: Bool {
        DCAppAttestService.shared.isSupported
    }

    var keyId: String? {
        KeychainService.string(forKey: Self.keyIdKey)
    }

    var isAttested: Bool {
        KeychainService.string(forKey: Self.isAttestedKey) == "true"
    }

    // MARK: - Migration

    /// Re-writes existing keychain items so they're readable while the device is
    /// locked (post first unlock). Older installs wrote items with the default
    /// `WhenUnlocked` accessibility, which blocked background transcription for
    /// watch-synced recordings received while the phone was locked overnight.
    func migrateKeychainAccessibilityIfNeeded() {
        let migrationKey = "appAttestKeychainAccessibilityMigrated"
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: migrationKey) else { return }

        if let existingKeyId = KeychainService.string(forKey: Self.keyIdKey) {
            KeychainService.setString(existingKeyId, forKey: Self.keyIdKey)
        }
        if let existingIsAttested = KeychainService.string(forKey: Self.isAttestedKey) {
            KeychainService.setString(existingIsAttested, forKey: Self.isAttestedKey)
        }
        defaults.set(true, forKey: migrationKey)
    }

    // MARK: - Key Generation

    /// Generates an App Attest key if one doesn't already exist. Returns the keyId.
    func generateKeyIfNeeded() async throws -> String {
        if let existing = keyId {
            return existing
        }
        let newKeyId = try await DCAppAttestService.shared.generateKey()
        KeychainService.setString(newKeyId, forKey: Self.keyIdKey)
        return newKeyId
    }

    // MARK: - Attestation

    /// Performs the full attestation flow: generate key, get server challenge,
    /// attest with Apple, register attestation with our server.
    /// Safe to call multiple times; no-ops if already attested or unsupported.
    func attestIfNeeded() async throws {
        guard isSupported else { return }
        guard !isAttested else { return }

        let keyId = try await generateKeyIfNeeded()

        // 1. Get a one-time challenge from the server
        let challenge = try await fetchChallenge()

        // 2. Hash the challenge to create clientDataHash
        let challengeData = Data(challenge.utf8)
        let clientDataHash = Data(SHA256.hash(data: challengeData))

        // 3. Attest the key with Apple's servers
        let attestation = try await DCAppAttestService.shared.attestKey(
            keyId, clientDataHash: clientDataHash
        )

        // 4. Send the attestation to our proxy for verification and storage
        try await registerAttestation(
            keyId: keyId, attestation: attestation, challenge: challenge
        )

        // 5. Mark as successfully attested
        KeychainService.setString("true", forKey: Self.isAttestedKey)
    }

    // MARK: - Assertion

    /// Generates an assertion for the given request body data.
    /// Returns nil if App Attest is unavailable or not yet attested.
    func generateAssertion(for requestData: Data) async -> (keyId: String, assertion: Data)? {
        guard isSupported, isAttested, let keyId = keyId else {
            return nil
        }

        let clientDataHash = Data(SHA256.hash(data: requestData))

        do {
            let assertion = try await DCAppAttestService.shared.generateAssertion(
                keyId, clientDataHash: clientDataHash
            )
            return (keyId: keyId, assertion: assertion)
        } catch let error as DCError where error.code == .invalidKey {
            // The key is genuinely gone (e.g. device restore, app reinstall).
            // Drop state so the next attempt re-attests.
            resetState()
            return nil
        } catch {
            // Transient failure (network, system busy, locked-keychain edge
            // cases). Leave attestation state intact so the retry can reuse it.
            return nil
        }
    }

    // MARK: - State Reset

    /// Clears all stored attestation state so a fresh key can be generated.
    func resetState() {
        KeychainService.delete(forKey: Self.keyIdKey)
        KeychainService.delete(forKey: Self.isAttestedKey)
    }

    // MARK: - Network Helpers

    private func fetchChallenge() async throws -> String {
        let settings = settingsService.load()
        guard let baseURLString = settings.transcriptionProvider.baseURL,
              let baseURL = URL(string: baseURLString) else {
            throw AppAttestError.serverNotConfigured
        }

        let url = baseURL.appendingPathComponent("attest/challenge")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(settings.deviceId, forHTTPHeaderField: "X-Device-ID")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw AppAttestError.challengeFailed
        }

        let result = try JSONDecoder().decode(ChallengeResponse.self, from: data)
        return result.challenge
    }

    private func registerAttestation(
        keyId: String, attestation: Data, challenge: String
    ) async throws {
        let settings = settingsService.load()
        guard let baseURLString = settings.transcriptionProvider.baseURL,
              let baseURL = URL(string: baseURLString) else {
            throw AppAttestError.serverNotConfigured
        }

        let url = baseURL.appendingPathComponent("attest")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(settings.deviceId, forHTTPHeaderField: "X-Device-ID")

        let body = AttestRegistration(
            keyId: keyId,
            attestation: attestation.base64EncodedString(),
            challenge: challenge
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw AppAttestError.attestationRejected
        }
    }
}

// MARK: - Error Types

enum AppAttestError: LocalizedError {
    case serverNotConfigured
    case challengeFailed
    case attestationRejected

    var errorDescription: String? {
        switch self {
        case .serverNotConfigured:
            return "Transcription server not configured"
        case .challengeFailed:
            return "Failed to get attestation challenge from server"
        case .attestationRejected:
            return "Server rejected device attestation"
        }
    }
}

// MARK: - Codable Types

private struct ChallengeResponse: Decodable {
    let challenge: String
}

private struct AttestRegistration: Encodable {
    let keyId: String
    let attestation: String
    let challenge: String
}
