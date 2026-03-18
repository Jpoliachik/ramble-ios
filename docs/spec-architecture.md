# Spec: Ramble Architecture

> Implementation spec for the Ramble rewrite. Defines the target system — what to build.

## Overview

Record audio → transcribe (on-device or via proxy) → store transcript locally → optionally POST to webhook.

No login. No accounts. No server-side user data. The app works out of the box with on-device transcription. Cloud API and webhook are opt-in.

## Data Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│  iPhone / Watch                                                 │
│                                                                 │
│  ┌──────────┐     ┌──────────────────────┐                      │
│  │  Record   │────▶│ TranscriptionQueue   │                      │
│  │  Audio    │     │ Service              │                      │
│  └──────────┘     └──────────┬───────────┘                      │
│                              │                                  │
│                   ┌──────────┴───────────┐                      │
│                   │                      │                      │
│                   ▼                      ▼                      │
│        ┌──────────────────┐   ┌──────────────────┐              │
│        │ Apple Speech     │   │ Proxy             │              │
│        │ (on-device)      │   │ Transcription     │              │
│        └────────┬─────────┘   └────────┬─────────┘              │
│                 │                      │                        │
│                 └──────────┬───────────┘                        │
│                            ▼                                    │
│                 ┌──────────────────┐                             │
│                 │ Store transcript  │                             │
│                 │ locally (JSON)    │                             │
│                 └────────┬─────────┘                             │
│                          │                                      │
│                          ▼                                      │
│                 ┌──────────────────┐     ┌──────────────────┐   │
│                 │ Display in app   │     │ WebhookQueue     │   │
│                 │                  │     │ Service           │   │
│                 └──────────────────┘     │ (optional POST)  │   │
│                                         └──────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
                                              │
                                              ▼
                                   ┌──────────────────┐
                                   │ User's webhook    │
                                   │ (agent, Zapier,   │
                                   │  n8n, etc.)       │
                                   └──────────────────┘
```

### Watch Flow

```
Watch: Record audio → Transfer file to phone via WatchConnectivity
Phone: Receive file → Feed into TranscriptionQueueService (same pipeline as phone recordings)
```

No changes to watch recording or transfer. The phone handles all transcription.

---

## Data Models

### Recording

```swift
struct Recording: Identifiable, Codable, Hashable {
    let id: UUID
    let createdAt: Date
    var duration: TimeInterval
    let audioFileName: String
    var status: RecordingStatus
    var transcription: String?
    var lastError: String?
    var webhookStatus: WebhookStatus?
}

enum RecordingStatus: String, Codable {
    case recorded       // Audio captured, ready for transcription
    case transcribing   // Transcription in progress
    case completed      // Transcript available
    case failed         // Transcription failed
}

enum WebhookStatus: String, Codable {
    case pending        // Queued for delivery
    case sending        // Currently sending
    case delivered      // 2xx received
    case failed         // All retries exhausted
    case skipped        // No webhook configured
}
```

Webhook status is **separate** from recording status. Transcription completing shows the transcript immediately. Webhook delivery happens in the background and never blocks the UI.

### TranscriptionJob

Single-phase job. Replaces the old two-phase UploadJob.

```swift
struct TranscriptionJob: Identifiable, Codable {
    let id: UUID
    let recordingId: UUID
    let provider: TranscriptionProvider  // Captured at enqueue time
    var retryCount: Int
    let createdAt: Date
    var nextRetryAt: Date?

    static let maxRetries = 5
    // Backoff: 5s, 15s, 45s, 90s, 180s
}
```

Provider is captured at enqueue time so mid-queue provider switches don't affect in-flight jobs.

### WebhookJob

```swift
struct WebhookJob: Identifiable, Codable {
    let id: UUID
    let recordingId: UUID
    var retryCount: Int
    let createdAt: Date
    var nextRetryAt: Date?

    static let maxRetries = 3
    // Backoff: 5s, 30s, 120s
}
```

### Settings

```swift
enum TranscriptionProvider: String, Codable, CaseIterable {
    case onDevice = "on_device"     // Apple Speech Recognition
    case proxy = "proxy"            // Cloud API via proxy
}

struct Settings: Codable {
    var transcriptionProvider: TranscriptionProvider  // Default: .onDevice
    var proxyBaseURL: String?       // Only used when provider == .proxy
    var webhookURL: String?         // Optional, for downstream automations
    var deviceId: String            // Auto-generated UUID, persisted forever
}
```

`deviceId` is generated once on first launch. Used for proxy usage tracking. Not tied to any account or personal identifier.

---

## Services

### TranscriptionService Protocol

```swift
struct TranscriptionRequest {
    let audioFileURL: URL
    let recordingId: UUID
    let duration: TimeInterval
}

struct TranscriptionResult {
    let text: String
}

protocol TranscriptionService {
    func transcribe(request: TranscriptionRequest) async throws -> TranscriptionResult
}
```

### AppleSpeechTranscriptionService

On-device transcription via `SFSpeechRecognizer`.

- Uses `SFSpeechURLRecognitionRequest` with the audio file
- `shouldReportPartialResults = false` — wait for final result
- `addsPunctuation = true`
- Handles permission requesting (`SFSpeechRecognizer.requestAuthorization`)
- No network required

```swift
class AppleSpeechTranscriptionService: TranscriptionService {
    func transcribe(request: TranscriptionRequest) async throws -> TranscriptionResult
}
```

### ProxyTranscriptionService

Sends audio to the stateless proxy API.

- Multipart POST with audio file
- Reads `proxyBaseURL` from Settings
- Sends `X-Device-ID` header
- Returns parsed transcript text

```swift
class ProxyTranscriptionService: TranscriptionService {
    func transcribe(request: TranscriptionRequest) async throws -> TranscriptionResult
}
```

### TranscriptionQueueService

Replaces `SyncQueueService`. Single-phase job queue.

**Responsibilities:**
- Maintain persistent queue (`transcription_queue.json`)
- Process one job at a time
- Dispatch to correct `TranscriptionService` based on job's provider
- Update Recording status: `recorded → transcribing → completed/failed`
- On completion: enqueue WebhookJob if webhook configured
- Retry with backoff on failure (5 retries max)

**Public API:**
```swift
@MainActor
class TranscriptionQueueService: ObservableObject {
    static let shared = TranscriptionQueueService()

    func enqueue(recordingId: UUID)
    func retry(recordingId: UUID)
    func resumePendingJobs()       // Scan for .recorded status, re-enqueue
    func processNextIfNeeded()
}
```

### WebhookQueueService

Independent queue for webhook delivery.

**Responsibilities:**
- Maintain persistent queue (`webhook_queue.json`)
- POST transcript JSON to webhook URL
- Update Recording.webhookStatus
- 3 retries with backoff
- If webhook URL removed from settings while jobs queued → mark as skipped

**Public API:**
```swift
@MainActor
class WebhookQueueService: ObservableObject {
    static let shared = WebhookQueueService()

    func enqueue(recordingId: UUID)
    func retry(recordingId: UUID)
    func processNextIfNeeded()
}
```

### TranscriptionError

```swift
enum TranscriptionError: Error, LocalizedError {
    case audioFileNotFound
    case recognitionUnavailable
    case recognitionDenied
    case noSpeechDetected
    case proxyNotConfigured
    case proxyError(statusCode: Int, message: String?)
    case networkError(Error)
}
```

---

## Proxy API Contract

The proxy is a thin stateless function (Cloudflare Worker or similar). It receives audio, forwards to a transcription provider (Groq, Deepgram, etc.), returns text. **Stores nothing.**

### POST /transcribe

**Request:**
```
POST /transcribe
Content-Type: multipart/form-data; boundary=...
X-Device-ID: <uuid>

--boundary
Content-Disposition: form-data; name="audio"; filename="recording.m4a"
Content-Type: audio/m4a

<binary audio data>
--boundary--
```

**Success Response (200):**
```json
{
  "text": "The full transcription text..."
}
```

**Error Responses:**

| Code | Meaning |
|------|---------|
| 400  | Bad request — no audio or unsupported format |
| 413  | Audio file too large |
| 429  | Rate limited — include `retry_after` in body |
| 500  | Transcription provider error |
| 503  | Provider unavailable |

All errors return: `{"error": "description"}`

### Usage Tracking

The proxy logs per-request: `(device_id, timestamp, audio_duration_seconds)`. Append-only. No audio or transcript stored.

This enables:
- Rate limiting per device
- Usage-based billing (future)
- Abuse prevention (block device IDs)

### No Auth Token

No authentication. Device ID is the identity key. The proxy trusts it for rate limiting. If billing is added later, device ID maps to payment.

---

## Webhook Contract

When a transcript completes and a webhook URL is configured, POST:

```json
{
  "recording_id": "uuid",
  "created_at": "2026-03-17T13:19:00Z",
  "duration": 138.5,
  "transcription": "The full transcript text...",
  "device_id": "uuid"
}
```

**To:** User-configured webhook URL
**Method:** POST
**Content-Type:** application/json
**Retries:** 3 attempts with backoff (5s, 30s, 120s)
**Success:** Any 2xx response

The app does not read or store the webhook response. Whatever happens downstream is not the app's concern.

---

## Settings UX

### Default Experience (new user)

1. Open app. No setup card. No configuration.
2. Tap record. Talk. Stop.
3. On-device transcription runs. Transcript appears in seconds.
4. Done.

**Zero setup required.** This is a dramatic improvement over the current flow.

### Settings Screen Layout

```
┌─────────────────────────────────────────┐
│ Settings                                │
│                                         │
│ ── Transcription ──────────────────────│
│                                         │
│ Provider:  [On-Device]  [Cloud API]     │
│                                         │
│ (if Cloud API:)                         │
│ Proxy URL: [________________________]   │
│            Requests are sent here.      │
│            No data is stored.           │
│                                         │
│ ── Webhook (Optional) ────────────────│
│                                         │
│ URL:       [________________________]   │
│            POST transcript to this URL  │
│            after each recording.        │
│                                         │
│ [Test Webhook]                          │
│                                         │
│ ── Stats ──────────────────────────────│
│                                         │
│ Recordings:  42                         │
│ Duration:    2h 15m                     │
│                                         │
│ ── Data ───────────────────────────────│
│                                         │
│ [Export All (JSON)]                     │
│                                         │
│ ── Danger Zone ────────────────────────│
│                                         │
│ [Delete All Data]                       │
│                                         │
└─────────────────────────────────────────┘
```

### Removed from Settings
- API token field
- Connection test button
- "Pending uploads" / "Failed uploads" language

### Updated Language
- "Pending uploads" → "Pending transcriptions"
- "Failed uploads" → "Failed transcriptions"
- "Syncing" → "Transcribing"

---

## Background Processing

`BackgroundTaskService` keeps the same two mechanisms:

1. **Immediate background (~30s)** — On app background, resume transcription queue + webhook queue
2. **BGProcessingTask** — Deferred processing for jobs that didn't complete

For on-device transcription: no network needed. Background processing works offline.
For proxy transcription: set `requiresNetworkConnectivity = true` on the BGProcessingTask.
For webhook delivery: needs network.

---

## Files to Create

| File | Purpose |
|------|---------|
| `Models/TranscriptionJob.swift` | Single-phase transcription job |
| `Models/WebhookJob.swift` | Webhook delivery job |
| `Services/TranscriptionService.swift` | Protocol + error types + request/result types |
| `Services/AppleSpeechTranscriptionService.swift` | On-device transcription |
| `Services/ProxyTranscriptionService.swift` | Proxy API transcription |
| `Services/TranscriptionQueueService.swift` | Job queue (replaces SyncQueueService) |
| `Services/WebhookQueueService.swift` | Webhook delivery queue |

## Files to Delete

| File | Reason |
|------|--------|
| `Models/UploadJob.swift` | Replaced by TranscriptionJob |
| `Services/SyncQueueService.swift` | Replaced by TranscriptionQueueService |
| `Services/RambleAPIClient.swift` | Replaced by ProxyTranscriptionService |
| `Views/SetupCardView.swift` | No setup needed — app works out of the box |

## Files to Modify

| File | Changes |
|------|---------|
| `Models/Recording.swift` | Remove agentNotes, new status enum, add webhookStatus |
| `Models/Settings.swift` | TranscriptionProvider, proxyBaseURL, webhookURL, deviceId |
| `Services/RecordingManager.swift` | `SyncQueueService` → `TranscriptionQueueService` |
| `Services/PhoneConnectivityService.swift` | Same swap |
| `Services/BackgroundTaskService.swift` | Point at new queue services |
| `RambleApp.swift` | Point at new queue services |
| `Views/SettingsView.swift` | New layout: provider picker, proxy URL, webhook URL |
| `ViewModels/SettingsViewModel.swift` | New fields, remove connection test |
| `Views/MainView.swift` | Remove SetupCardView, update banner |
| `Views/SyncStatusBannerView.swift` | Update copy ("transcribing" not "syncing") |
| `Views/RecordingDetailView.swift` | Remove agent notes section, add webhook status indicator |
| `Views/RecordingRowView.swift` | Update status display |
| `ViewModels/RecordingViewModel.swift` | Swap queue service references |

---

## Implementation Sequence

Ordered so the project builds at each step:

1. **Models** — Recording, Settings, TranscriptionJob, WebhookJob
2. **Protocol + implementations** — TranscriptionService, AppleSpeech, Proxy
3. **Queue services** — TranscriptionQueueService, WebhookQueueService
4. **Wiring** — RecordingManager, PhoneConnectivity, BackgroundTask, RambleApp
5. **UI** — Settings, MainView, DetailView, Banner, RowView, ViewModels
6. **Delete dead code** — UploadJob, SyncQueueService, RambleAPIClient, SetupCardView

---

## Edge Cases

| Scenario | Behavior |
|----------|----------|
| Transcription fails | Status → failed, lastError set. User can retry. Webhook not triggered. |
| Webhook fails | Transcript still visible. webhookStatus → failed. User can retry webhook separately. |
| User switches provider mid-queue | In-flight jobs keep their original provider. New recordings use new provider. |
| User removes webhook URL while jobs queued | Queued webhook jobs marked as skipped. |
| No speech detected | Status → failed with "No speech detected" error. |
| Offline + on-device | Works fine. No network needed. |
| Offline + proxy | Job stays in queue. Retries when network available. |
| Watch recording received | Enters same transcription pipeline as phone recording. |

---

## Open Questions (to resolve during implementation)

- [ ] iOS 26 Speech Recognition — What's new? Better quality? New APIs?
- [ ] Proxy hosting — Cloudflare Workers? Vercel? What's cheapest/simplest?
- [ ] Audio size limits — What's the max file size the proxy should accept?
- [ ] Rate limiting details — What limits per device? How communicated?
- [ ] Business model — Flat fee? Usage-based? Free tier limits?
