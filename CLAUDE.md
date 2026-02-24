# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Ramble** is a personal voice journaling iOS app for Justin. Core flow: voice recording → upload to backend → transcription + LLM extraction → searchable archive. The goal is frictionless daily capture (< 3 seconds from intent to talking) that builds a rich, searchable record of thoughts and activities.

### Key Principles

- **For Justin only** — Optimize for one person's workflow, not generic "users"
- **Capture over organization** — Messy input beats no input; structure comes later
- **LLM-native** — Design data formats assuming LLMs will process them
- **Plain text wins** — Markdown files, no proprietary formats or complex databases
- **Don't overbuild** — Ship minimal, use it, iterate based on real use

See `docs/VISION.md` for full product vision and iteration phases.

## Build & Development

This is a native iOS project using Xcode. No CocoaPods or SPM dependencies.

```bash
# Open in Xcode
open Ramble/Ramble.xcodeproj

# Build iOS app
xcodebuild -project Ramble/Ramble.xcodeproj -scheme Ramble -destination 'platform=iOS Simulator,name=iPhone 17 Pro'

# Build watch app
xcodebuild -project Ramble/Ramble.xcodeproj -scheme "watch Watch App" -destination 'platform=watchOS Simulator,name=Apple Watch Series 11 (46mm)'
```

## Architecture

### Targets

- **Ramble** — Main iOS app (SwiftUI)
- **watch Watch App** — watchOS companion app

### Source Layout

```
Ramble/
├── Ramble/           # Main iOS app source
├── watch Watch App/  # watchOS companion
└── Ramble.xcodeproj/
```

### Data Flow

1. **Record** — AudioRecorderService captures 16kHz mono AAC audio
2. **Upload** — SyncQueueService uploads audio + metadata to backend via RambleAPIClient
3. **Poll** — SyncQueueService polls GET /ramble/recordings/{id} for results
4. **Display** — Recording model updated with transcription + agent_notes from backend

### Key Services

| Service | Role |
|---------|------|
| `RambleAPIClient` | HTTP client — multipart upload + JSON polling |
| `SyncQueueService` | Persistent job queue — upload phase then poll phase with backoff |
| `BackgroundTaskService` | UIKit + BGProcessingTask for background sync |
| `RecordingManager` | Coordinates audio recording lifecycle |
| `StorageService` | JSON file persistence for recordings |
| `PhoneConnectivityService` | WatchConnectivity bridge for watch recordings |

### Models

- `Recording` — Core model: id, createdAt, duration, audioFileName, status, transcription, agentNotes, lastError
- `RecordingStatus` — recorded → uploading → processing → completed / failed
- `UploadJob` — Two-phase job (upload then poll) with retry backoff
- `Settings` — apiBaseURL + apiToken

### Tech Stack

- SwiftUI for all UI
- Deployment target: iOS 26.2, watchOS 26.2

### Backend API

The app communicates with a backend via 3 endpoints:
- `POST /ramble/recordings` — Upload audio (multipart)
- `GET /ramble/recordings/{id}` — Poll for transcription + agent notes
- `DELETE /ramble/recordings/{id}` — Delete recording from backend

Full API spec: `.claude/skills/ramble-backend/SKILL.md`

## Current Phase

**Phase 1: Capture** — Building the recording → upload → processing flow. Focus on making it fast and reliable enough for daily use.
