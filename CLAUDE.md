# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Ramble** is a voice-to-text capture app for iOS + watchOS. Core flow: tap record → talk → transcript appears. The goal is frictionless capture (< 3 seconds from intent to talking) from any surface — phone, watch, CarPlay, Siri.

### Key Principles

- **Nothing ever gets lost** — Offline-first, persistent queues, clear status
- **Capture over organization** — Messy input beats no input; structure comes later
- **No user data on servers** — Privacy by architecture. No login, no accounts.
- **Pluggable, not opinionated** — Users choose transcription provider. Webhook for downstream.
- **Ship and iterate** — Don't overbuild. Use it, notice what's missing, add that.

See `docs/VISION.md` for product vision, `docs/BRAND.md` for brand guide.

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
2. **Transcribe** — TranscriptionQueueService dispatches to on-device (Apple Speech) or proxy API
3. **Store** — Transcript saved locally to Recording model
4. **Webhook** — Optional POST of transcript to user-configured URL

### Key Services

| Service | Role |
|---------|------|
| `TranscriptionQueueService` | Persistent job queue — single-phase transcription with retry |
| `AppleSpeechTranscriptionService` | On-device transcription via SFSpeechRecognizer |
| `ProxyTranscriptionService` | HTTP client — sends audio to stateless proxy API |
| `WebhookQueueService` | Independent queue for webhook delivery |
| `BackgroundTaskService` | UIKit + BGProcessingTask for background processing |
| `RecordingManager` | Coordinates audio recording lifecycle |
| `StorageService` | JSON file persistence for recordings |
| `PhoneConnectivityService` | WatchConnectivity bridge for watch recordings |

### Models

- `Recording` — Core model: id, createdAt, duration, audioFileName, status, transcription, webhookStatus, lastError
- `RecordingStatus` — recorded → transcribing → completed / failed
- `TranscriptionJob` — Single-phase job with retry backoff
- `WebhookJob` — Webhook delivery job with retry
- `Settings` — transcriptionProvider, proxyBaseURL, webhookURL, deviceId

### Tech Stack

- SwiftUI for all UI
- Deployment target: iOS 26.2, watchOS 26.2

### Proxy API

Thin stateless function (Cloudflare Worker or similar). Receives audio, forwards to transcription provider, returns text. Stores nothing.

- `POST /transcribe` — Multipart audio in, `{"text": "..."}` out
- `X-Device-ID` header for usage tracking

Full architecture spec: `docs/spec-architecture.md`

## Current Phase

**Architecture rewrite** — Migrating from backend-dependent upload→poll model to local-first transcription with optional webhook. See `docs/spec-architecture.md`.

## Product Notes — 2026-03-23

### Strategy Pivot: Open Source Release
- Dropping the wellness/lifestyle brand marketing angle — too much effort for the brand side
- New plan: open source implementation, release on App Store as a clean, useful utility
- Goal: put Justin's name on something polished, get community input, open source contribution visibility
- Milestone target: get it on the App Store — that's the ship
- Keep it simple: it's a good little project, don't over-engineer the brand story around it
