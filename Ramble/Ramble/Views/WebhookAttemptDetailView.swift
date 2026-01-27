//
//  WebhookAttemptDetailView.swift
//  Ramble
//

import SwiftUI

struct WebhookAttemptDetailView: View {
    let attempt: WebhookAttempt

    var body: some View {
        List {
            Section("Request") {
                row(label: "Method", value: "POST")
                row(label: "URL", value: attempt.url, monospaced: true)
            }

            Section("Response") {
                row(label: "Status", value: statusText)
                if let statusCode = attempt.statusCode {
                    row(label: "HTTP Code", value: "\(statusCode)")
                }
                if let error = attempt.errorMessage {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Error")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text(error)
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.red)
                            .textSelection(.enabled)
                    }
                    .padding(.vertical, 2)
                }
            }

            Section("Timing") {
                row(label: "Sent At", value: DateFormatters.fullFormatter.string(from: attempt.timestamp))
                if let durationMs = attempt.durationMs {
                    row(label: "Duration", value: formatDuration(durationMs))
                }
            }
        }
        .navigationTitle("Webhook Attempt")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var statusText: String {
        attempt.success ? "Success" : "Failed"
    }

    private func row(label: String, value: String, monospaced: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text(value)
                .font(monospaced ? .system(.body, design: .monospaced) : .body)
                .textSelection(.enabled)
        }
        .padding(.vertical, 2)
    }

    private func formatDuration(_ ms: Int) -> String {
        if ms < 1000 {
            return "\(ms)ms"
        } else {
            let seconds = Double(ms) / 1000.0
            return String(format: "%.2fs", seconds)
        }
    }
}

extension DateFormatters {
    static let fullFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter
    }()
}

#Preview {
    NavigationStack {
        WebhookAttemptDetailView(attempt: WebhookAttempt(
            url: "https://example.com/webhook",
            success: false,
            statusCode: 500,
            errorMessage: "Internal Server Error: The server encountered an unexpected condition.",
            durationMs: 1234
        ))
    }
}
