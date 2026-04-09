# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Ramble** is an open-source voice-to-text capture app for iPhone + Apple Watch. Tap record, talk, get a transcript. That's the whole thing. Apple-only — no Android, no web.

No accounts, no servers, no data leaving your device unless you tell it to. Open source — the codebase is the proof.

### Three audiences

1. **General users** — want reliable Apple Watch voice notes. Record a thought on a hike, get a clean transcript when you get home. Apple Speech, no setup, just works.
2. **Power users** — want better transcription quality and are willing to pay for it. $2.99/month subscription (via App Store) unlocks cloud transcription models (Groq Whisper, Deepgram Nova-3, OpenAI GPT-4o Transcribe).
3. **Technical users** — want to pipe voice into their agent/automation via webhook (OpenClaw, custom setups, etc.) or point at their own transcription endpoint.

The primary marketing pitch is **Apple Watch voice capture**. Record anywhere, get your transcript back. That's the hook. The power user upgrade and webhook/automation stuff is there for people who want it, but the core story is simple and universal.

### What Ramble is

A voice input device with a great UX. A dumb pipe that captures beautifully and gets out of your way. Record, transcribe, store locally, optionally POST to webhook.

### What Ramble is NOT

- Not a note-taking app (captures voice, gives you text — what you do with it is your business)
- Not an AI assistant (no built-in LLM features — webhook is the extensibility model)
- Not a platform (no accounts, no backend, no server-side data)

### Design Principles

1. **Nothing ever gets lost** — Offline-first, persistent queues, clear status at all times. Core promise.
2. **Capture over organization** — Messy input beats no input. Structure comes later.
3. **No user data on servers** — Privacy by architecture. No login, no accounts. Open source proves it.
4. **Pluggable, not opinionated** — Users choose transcription provider. Webhook for downstream. Don't lock anyone in.
5. **Ship and iterate** — Don't overbuild. Use it, notice what's missing, add that. Free app with a small paid upgrade.

## Current Phase

**v1 push to App Store** — Local-first architecture is in place. Focus is reliability (queues, retry, status transparency), watch sync, and UX polish. Then ship.

### v1 scope

- iOS: record → transcribe → browse/copy transcripts, settings for proxy + webhook
- Watch: record, sync to phone, minimal recordings list (timestamp, duration, sync status)
- StoreKit 2 subscription for cloud transcription ($2.99/month)
- NOT in v1: CarPlay, widgets, Siri, full-text search, tags/folders, watch complication

### Release plan

- Open source the repo on GitHub
- Free app on App Store (Apple Speech on-device transcription + webhook — costs nothing to run)
- $2.99/month subscription unlocks cloud transcription models via Cloudflare Worker proxy
- Marketing website (simple, separate repo/session)

## Strategy

- Open source the repo — privacy proof is in the codebase, no backend
- Apple ecosystem only (iPhone + Apple Watch) — not cross-platform
- Free app on App Store, Apple Speech default (free, private, improving)
- $2.99/month subscription via App Store for cloud transcription (Groq Whisper, Deepgram Nova-3, OpenAI GPT-4o Transcribe) — the only thing that costs money to run
- Optional custom transcription endpoint URL (bring your own: Groq, Deepgram, self-hosted, etc.)
- Optional webhook URL for downstream processing (fire and forget)

### The trust contract: nothing ever gets lost

If someone records a thought on their watch during a hike and the transcript isn't there when they get home, they'll never use the app again.

- **Persistent queues** — Every recording, transcription job, and webhook delivery is queued and retried until it succeeds or the user explicitly dismisses it
- **Clear status everywhere** — Every recording shows its exact state at all times. No mystery spinners, no silent failures
- **Transparent errors** — When something fails, say what failed and why. Offer a retry button
- **Background processing** — Scheduled jobs to drain queues when the app isn't in the foreground
- **Watch sync is solid** — Recordings made on the watch sync to the phone reliably. Queue is visible, nothing gets dropped

### Transcription strategy

**Default: Apple Speech (on-device).** Free, private, zero setup. Out-of-box experience.

**Upgrade: Cloud transcription ($2.99/month).** For users who want better accuracy, a subscription unlocks cloud models (Groq Whisper, Deepgram Nova-3, OpenAI GPT-4o Transcribe) routed through our Cloudflare Worker proxy. The proxy is open source — users can verify no data is stored. Subscription via StoreKit 2 / App Store.

**Custom endpoint: Bring your own.** Point Ramble at any URL that accepts audio and returns text. Same pattern: just a URL in settings. No subscription required.

### Privacy

- No login. No accounts. No analytics. No telemetry.
- All data stays on device.
- Open source — anyone can verify there's no backend.
- Webhook/proxy only sends data if the user explicitly configures it.

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
├── Ramble/          # Main iOS app source
├── watch Watch App/  # watchOS companion
└── Ramble.xcodeproj/
```

### Data Flow

1. **Record** — AudioRecorderService captures 16kHz mono AAC audio
2. **Transcribe** — TranscriptionQueueService dispatches to on-device (Apple Speech) or custom endpoint
3. **Store** — Transcript saved locally to Recording model
4. **Webhook** — Optional POST of transcript to user-configured URL

### Key Services

| Service | Role |
|---------|------|
| `AudioRecorderService` | 16kHz mono AAC capture |
| `TranscriptionQueueService` | Persistent job queue with retry |
| `AppleSpeechTranscriptionService` | On-device transcription via SFSpeechRecognizer (default) |
| `ProxyTranscriptionService` | HTTP client for custom transcription endpoints |
| `WebhookQueueService` | Independent queue for webhook delivery with retry |
| `BackgroundTaskService` | UIKit + BGProcessingTask for background queue draining |
| `RecordingManager` | Coordinates audio recording lifecycle |
| `StorageService` | JSON file persistence for recordings |
| `PhoneConnectivityService` | WatchConnectivity bridge for watch recordings |

### Models

- `Recording` — Core model: id, createdAt, duration, audioFileName, status, transcription, webhookStatus, lastError
- `RecordingStatus` — recorded → transcribing → completed / failed
- `TranscriptionJob` — Single-phase job with retry backoff
- `WebhookJob`  — Webhook delivery job with retry
- `Settings` — transcriptionProvider, webhookEnabled, webhookURL, webhookSecret, deviceId

### Tech Stack

- SwiftUI for all UI
- Deployment target: iOS 26.2, watchOS 26.2

### Proxy API

Thin stateless function (Cloudflare Worker or similar). Receives audio, forwards to transcription provider, returns text. Stores nothing.

- `POST /transcribe` — Multipart audio in, `{"text": "..."}` out
- `X-Device-ID` header for usage tracking

Full architecture spec: `docs/spec-architecture.md`

## Brand & Voice

**Tagline:** Tap. Talk. It's captured.

**Tone:** Calm, short, human, honest. No hype, no startup language, no "AI-powered" selling points. Promise reliability, not transformation.

**Visual:** Clean and warm. Sage/stone/cream palette. SF Pro. Simple waveform logo that works at watch-complication size.


### App Store Description (draft)

> Tap. Talk. It's captured.
>
> Ramble turns your voice into text, instantly. No account. No setup. Your words stay on your device.
>
> Record from your phone or your watch. Every thought gets transcribed and saved — ready to copy, search, or send anywhere via webhook.
>
> Open source. No servers. Your thoughts, your data.

## Pre-Launch Checklist

### Proxy endpoint authentication — DONE

Apple App Attest is implemented. Client-side attestation via `DCAppAttestService` proves requests come from a legitimate copy of Ramble on a real Apple device. Assertion sent with each cloud transcription request, verified server-side.

Server-side rate limiting (Cloudflare KV, per-device caps) is a nice-to-have cost safety net but not a blocker — App Attest is the primary defense.

### Remaining v1 work

- [ ] **Watch recordings list** — minimal list showing timestamp, duration, and sync status for each recording
- [ ] **StoreKit 2 subscription** — $2.99/month for cloud transcription, gate cloud models behind active subscription
- [ ] **Launch screen** — splash screen for app launch
- [ ] **App Store assets** — screenshots (iPhone + Apple Watch), privacy policy URL, app description
- [ ] **Marketing website** — simple landing page (separate session/repo)

## Resolved Questions

- **Transcript browsing UX for v1:** Just scroll the list. No search, no tags, no folders.
- **Watch complication:** Not in v1.
- **Pricing:** Free app + $2.99/month subscription for cloud transcription. On-device Apple Speech and webhook are free.
- **Platform:** Apple only (iPhone + Apple Watch). No Android, no web.
