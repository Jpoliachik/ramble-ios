# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Ramble** is an open-source voice capture app for iPhone + Apple Watch. Record your thoughts on the go, get accurate transcripts, and pipe them into your agent, workflow, or automation via webhook. Open source, private by design, no accounts.

For full brand positioning, audience, tone, and messaging guidelines, see **`docs/brand.md`**.

## Current Phase

**v1 push to App Store** — Local-first architecture is in place. Focus is reliability (queues, retry, status transparency), watch sync, and UX polish. Then ship.

### v1 scope

- iOS: record → transcribe → browse/copy transcripts, settings for proxy + webhook
- Watch: record, sync to phone, minimal recordings list (timestamp, duration, sync status)
- StoreKit 2 subscription for cloud transcription ($3.99/month)
- NOT in v1: CarPlay, widgets, Siri, full-text search, tags/folders, watch complication

### Remaining v1 work

- [ ] **App Store assets** — screenshots (iPhone + Apple Watch), privacy policy URL, app description
- [ ] **End-to-end production testing** — verify real StoreKit subscription flow (sandbox/TestFlight), JWS verification on proxy, and cloud transcription without dev bypass
- [ ] **Transcript formatting** — transcripts render as one big block of text with no line breaks. Improve formatting with paragraph breaks (Apple Speech segments, cloud provider paragraph support, or heuristic sentence grouping)
- [ ] **Recording detail title** — show date/time instead of "Recording" in the navigation title on RecordingDetailView

### Post-v1 — cloud transcription enhancements

These are free features from existing providers (no extra API calls or cost):

- [ ] **Deepgram auto-paragraphs** — add `paragraphs=true` to Deepgram API call; instant readability improvement for longer recordings
- [ ] **Filler word removal toggle** — settings toggle to strip "um", "uh", etc. Deepgram supports natively; client-side regex for Groq/OpenAI
- [ ] **Speaker diarization** — opt-in toggle. Deepgram has `diarize=true`, OpenAI has `gpt-4o-transcribe-diarize` model. Labels speakers in transcript. Great for conversations/meetings.
- [ ] **Language hint** — language picker in settings, passed to all providers. Improves accuracy for non-English users.

### Future

- [ ] **Localization** — translate the app UI into additional languages

### Release plan

- Open source the repo on GitHub
- Free app on App Store (Apple Speech on-device transcription + webhook — costs nothing to run)
- $3.99/month subscription unlocks cloud transcription models via Cloudflare Worker proxy
- Marketing website at `goodloop.dev/ramble` (source in `website/`, static export)
- **App Store URL:** https://apps.apple.com/app/id6761857751 (Apple ID: 6761857751)

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

### Website

```bash
cd website
npm install
npm run build    # Static export to website/out/
npm run dev      # Dev server at localhost:3000/ramble
```

The site is configured with `basePath: "/ramble"` and `output: "export"`. The `out/` directory contains plain HTML/CSS/JS — copy it into the goodloop.dev repo to serve at `goodloop.dev/ramble`. No server runtime needed.

**Pages:** Landing (`/`), Privacy Policy (`/privacy`), Terms of Use (`/terms`), Webhook API Docs (`/docs`)

## Architecture

### Targets

- **Ramble** — Main iOS app (SwiftUI)
- **watch Watch App** — watchOS companion app

### Source Layout

```
Ramble/
├── Ramble/            # Main iOS app source
├── watch Watch App/   # watchOS companion
└── Ramble.xcodeproj/
website/               # Marketing site (Next.js static export)
proxy/                 # Cloudflare Worker transcription proxy
```

### Data Flow

1. **Record** — AudioRecorderService captures 16kHz mono AAC audio
2. **Transcribe** — TranscriptionQueueService dispatches to on-device (Apple Speech) or cloud endpoint
3. **Store** — Transcript saved locally to Recording model
4. **Webhook** — Optional POST of transcript to user-configured URL

### Key Services

| Service | Role |
|---------|------|
| `AudioRecorderService` | 16kHz mono AAC capture |
| `TranscriptionQueueService` | Persistent job queue with retry |
| `AppleSpeechTranscriptionService` | On-device transcription via SFSpeechRecognizer (default) |
| `ProxyTranscriptionService` | HTTP client for cloud/custom transcription endpoints |
| `WebhookQueueService` | Independent queue for webhook delivery with retry |
| `BackgroundTaskService` | UIKit + BGProcessingTask for background queue draining |
| `RecordingManager` | Coordinates audio recording lifecycle |
| `StorageService` | JSON file persistence for recordings |
| `PhoneConnectivityService` | WatchConnectivity bridge for watch recordings |

### Models

- `Recording` — Core model: id, createdAt, duration, audioFileName, status, transcription, webhookStatus, lastError
- `RecordingStatus` — recorded → transcribing → completed / failed
- `TranscriptionJob` — Single-phase job with retry backoff
- `WebhookJob` — Webhook delivery job with retry
- `Settings` — transcriptionProvider, cloudModel, webhookEnabled, webhookURL, webhookSecret, deviceId

### Tech Stack

- SwiftUI for all UI
- Deployment target: iOS 26.2, watchOS 26.2

### Proxy API

Thin stateless Cloudflare Worker. Receives audio, forwards to transcription provider, returns text. Stores nothing. Protected by Apple App Attest.

- `POST /transcribe` — Multipart audio in, `{"text": "..."}` out
- `X-Device-ID` header for usage tracking

### Cloud Transcription Models

| Model | Provider | Strength |
|-------|----------|----------|
| Whisper v3 Turbo | Groq | Fast and accurate — best all-around (default) |
| Whisper Large v3 | Groq | Best for accents and multilingual audio |
| Nova-3 | Deepgram | Strong English accuracy, smart formatting |
| GPT-4o Transcribe | OpenAI | Highest accuracy in noisy environments |

## Pre-Launch Checklist

### Proxy endpoint authentication — DONE

Apple App Attest implemented. Client-side attestation via `DCAppAttestService` proves requests come from a legitimate copy of Ramble on a real Apple device. Assertion sent with each cloud transcription request, verified server-side.

## Resolved Questions

- **Transcript browsing UX for v1:** Just scroll the list. No search, no tags, no folders.
- **Watch complication:** Not in v1.
- **Pricing:** Free app + $3.99/month subscription for cloud transcription. On-device Apple Speech and webhook are free.
- **Platform:** Apple only (iPhone + Apple Watch). No Android, no web.
