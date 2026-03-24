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

**v1 push to App Store** — Local-first architecture is in place. Focus is reliability (queues, retry, status transparency), watch sync, and UX polish. Then ship.

## Product Direction

### What Ramble is
An open-source voice capture utility. Record, transcribe, store locally, optionally POST to webhook. A "dumb pipe" with a great UX — it's the input device, not the brain.

### Two audiences
1. **General users** — want fast voice-to-text capture that works out of the box (Apple Speech, no setup)
2. **Technical users** — want to pipe voice into their agent/automation via webhook (OpenClaw, custom setups, etc.)

### Strategy
- Open source the repo — privacy proof is in the codebase, no backend
- Free app on App Store
- Apple Speech as default transcription (free, private, improving)
- Optional custom transcription endpoint URL (Groq, Deepgram, self-hosted, etc.)
- Optional webhook URL for downstream processing (fire and forget)
- Reference Cloudflare Worker proxy for users who want third-party transcription APIs

### Core promise: nothing ever gets lost
- Persistent queues with retry for transcription and webhook delivery
- Clear status on every recording at all times — no mystery spinners
- Transparent errors with manual retry
- Background processing via scheduled jobs
- Watch recordings sync reliably to phone

### v1 scope
- iOS: record → transcribe → browse/copy transcripts, settings for proxy + webhook
- Watch: record, sync to phone, queue status visible
- NOT in v1: CarPlay, widgets, Siri, full-text search, tags/folders
