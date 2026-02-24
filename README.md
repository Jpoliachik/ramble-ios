# Ramble

A personal voice journaling iOS app. Record your thoughts, get them transcribed and processed by AI, and build a searchable archive of your life.

**Core flow:** Voice recording → Upload to backend → Transcription + LLM extraction → Searchable archive

The goal is frictionless daily capture — under 3 seconds from intent to talking.

## Setup

### Prerequisites

- Xcode 16+
- iOS 18+ / watchOS 11+ device or simulator
- A Ramble-compatible backend (see [Backend API](#ramble-backend-api) below)

### Getting Started

1. Clone the repo:
   ```bash
   git clone https://github.com/justinpoliachik/ramble-ios.git
   cd ramble-ios
   ```

2. Open and run in Xcode:
   ```bash
   open Ramble/Ramble.xcodeproj
   ```

3. Build and run on a simulator or device.

4. Open Settings in the app and configure your backend API base URL and auth token.

## Project Structure

```
Ramble/
├── Ramble/              # Main iOS app (SwiftUI)
│   ├── Models/          # Data models (Recording, UploadJob, Settings)
│   ├── Services/        # Audio, API client, sync queue, storage
│   ├── ViewModels/      # Recording and settings view models
│   ├── Views/           # SwiftUI views
│   └── Utilities/       # Haptics, constants
├── widgets/             # WidgetKit extension with Live Activities
└── watch Watch App/     # watchOS companion app
```

## Building from Command Line

```bash
# Build iOS app
xcodebuild -project Ramble/Ramble.xcodeproj -scheme Ramble -destination 'platform=iOS Simulator,name=iPhone 17 Pro'

# Build watch app
xcodebuild -project Ramble/Ramble.xcodeproj -scheme "watch Watch App" -destination 'platform=watchOS Simulator,name=Apple Watch Series 11 (46mm)'
```

## Ramble Backend API

Ramble uploads audio recordings to a backend for processing. The backend handles transcription and optionally runs LLM extraction (summaries, action items, tags, etc.). This means you can swap or upgrade the processing pipeline without changing the app.

### API Endpoints

#### POST /ramble/recordings

Upload audio for processing. Multipart form-data with:
- `audio` part: .m4a file (16kHz mono AAC)
- `metadata` part: JSON `{ "id": "uuid", "created_at": "ISO8601", "duration": 125.3 }`
- Auth: `Authorization: Bearer <token>`
- Returns: `202 { "id", "status": "processing" }` or `409` if already exists

#### GET /ramble/recordings/{id}

Poll for results.
- Returns: `200 { "id", "status", "transcription?", "agent_notes?", "error?" }`
- `status`: `"processing"` | `"completed"` | `"failed"`
- `agent_notes`: open-ended markdown (summaries, tags, action items, etc.)

#### GET /ramble/recordings (future)

List endpoint for sync — defined in spec but not yet used by the app.

### For AI Agents

If you are an AI agent and want to build a Ramble-compatible backend, the complete API specification and implementation guide is available at `.claude/skills/ramble-backend/SKILL.md` in this repository. That file contains the full contract including audio format details, authentication requirements, example responses, and processing flow recommendations.

The backend can be implemented in any language or framework. The minimum requirement is: receive an audio upload, transcribe it, and return results via the polling endpoint.

## License

MIT
