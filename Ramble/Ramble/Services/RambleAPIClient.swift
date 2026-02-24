//
//  RambleAPIClient.swift
//  Ramble
//

import Foundation

enum APIError: Error, LocalizedError {
    case notConfigured
    case fileNotFound
    case unauthorized
    case conflict
    case serverError(Int, String?)
    case networkError(Error)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "API not configured — set base URL and token in Settings"
        case .fileNotFound: return "Audio file not found"
        case .unauthorized: return "Unauthorized — check your API token"
        case .conflict: return "Recording already exists"
        case .serverError(let code, let msg): return "Server error \(code): \(msg ?? "unknown")"
        case .networkError(let err): return "Network error: \(err.localizedDescription)"
        case .invalidResponse: return "Invalid server response"
        }
    }
}

enum ConnectionTestResult {
    case success
    case notConfigured
    case unauthorized
    case networkError(String)
    case serverError(Int, String?)
}

struct UploadResponse: Decodable {
    let id: String
    let status: String
}

struct RecordingResponse: Decodable {
    let id: String
    let status: String
    let transcription: String?
    let agent_notes: String?
    let error: String?
}

final class RambleAPIClient {
    static let shared = RambleAPIClient()

    private let settingsService = SettingsService.shared

    private init() {}

    var isConfigured: Bool {
        let settings = settingsService.load()
        guard let baseURL = settings.apiBaseURL, !baseURL.isEmpty else { return false }
        return URL(string: baseURL) != nil
    }

    // MARK: - POST /ramble/recordings

    struct UploadParams {
        let recording: Recording
        let audioData: Data
    }

    func uploadRecording(params: UploadParams) async throws -> UploadResponse {
        let (baseURL, token) = try resolveEndpoint()
        let url = baseURL.appendingPathComponent(Constants.recordingsPath)

        let boundary = UUID().uuidString
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if let token = token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        var body = Data()

        // Audio part
        body.appendString("--\(boundary)\r\n")
        body.appendString("Content-Disposition: form-data; name=\"audio\"; filename=\"\(params.recording.audioFileName)\"\r\n")
        body.appendString("Content-Type: audio/m4a\r\n\r\n")
        body.append(params.audioData)
        body.appendString("\r\n")

        // Metadata part
        let metadata: [String: Any] = [
            "id": params.recording.id.uuidString,
            "created_at": ISO8601DateFormatter().string(from: params.recording.createdAt),
            "duration": params.recording.duration
        ]
        let metadataJSON = try JSONSerialization.data(withJSONObject: metadata)
        body.appendString("--\(boundary)\r\n")
        body.appendString("Content-Disposition: form-data; name=\"metadata\"\r\n")
        body.appendString("Content-Type: application/json\r\n\r\n")
        body.append(metadataJSON)
        body.appendString("\r\n")

        // End boundary
        body.appendString("--\(boundary)--\r\n")

        request.httpBody = body

        let (data, response) = try await performRequest(request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 202:
            return try JSONDecoder().decode(UploadResponse.self, from: data)
        case 401:
            throw APIError.unauthorized
        case 409:
            throw APIError.conflict
        default:
            let msg = String(data: data, encoding: .utf8)
            throw APIError.serverError(httpResponse.statusCode, msg)
        }
    }

    // MARK: - GET /ramble/recordings/{id}

    func getRecording(id: UUID) async throws -> RecordingResponse {
        let (baseURL, token) = try resolveEndpoint()
        let url = baseURL.appendingPathComponent(Constants.recordingsPath)
            .appendingPathComponent(id.uuidString)

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        if let token = token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await performRequest(request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            return try JSONDecoder().decode(RecordingResponse.self, from: data)
        case 401:
            throw APIError.unauthorized
        default:
            let msg = String(data: data, encoding: .utf8)
            throw APIError.serverError(httpResponse.statusCode, msg)
        }
    }

    // MARK: - Test Connection

    func testConnection() async -> ConnectionTestResult {
        guard isConfigured else { return .notConfigured }

        do {
            let (baseURL, token) = try resolveEndpoint()
            let url = baseURL.appendingPathComponent(Constants.recordingsPath)

            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            if let token = token {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }

            let (data, response) = try await performRequest(request)

            guard let httpResponse = response as? HTTPURLResponse else {
                return .serverError(0, "Invalid response")
            }

            switch httpResponse.statusCode {
            case 200...299, 404:
                return .success
            case 401:
                return .unauthorized
            default:
                let msg = String(data: data, encoding: .utf8)
                return .serverError(httpResponse.statusCode, msg)
            }
        } catch let error as APIError {
            switch error {
            case .notConfigured: return .notConfigured
            case .unauthorized: return .unauthorized
            case .networkError(let err): return .networkError(err.localizedDescription)
            case .serverError(let code, let msg): return .serverError(code, msg)
            default: return .networkError(error.localizedDescription)
            }
        } catch {
            return .networkError(error.localizedDescription)
        }
    }

    // MARK: - DELETE /ramble/recordings/{id}

    func deleteRecording(id: UUID) async throws {
        let (baseURL, token) = try resolveEndpoint()
        let url = baseURL.appendingPathComponent(Constants.recordingsPath)
            .appendingPathComponent(id.uuidString)

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        if let token = token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await performRequest(request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200...299:
            return
        case 401:
            throw APIError.unauthorized
        case 404:
            return // Already deleted, treat as success
        default:
            let msg = String(data: data, encoding: .utf8)
            throw APIError.serverError(httpResponse.statusCode, msg)
        }
    }

    // MARK: - Helpers

    private func resolveEndpoint() throws -> (URL, String?) {
        let settings = settingsService.load()
        guard let baseURLString = settings.apiBaseURL,
              !baseURLString.isEmpty,
              let baseURL = URL(string: baseURLString) else {
            throw APIError.notConfigured
        }
        return (baseURL, settings.apiToken)
    }

    private func performRequest(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await URLSession.shared.data(for: request)
        } catch {
            throw APIError.networkError(error)
        }
    }
}

private extension Data {
    mutating func appendString(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}
