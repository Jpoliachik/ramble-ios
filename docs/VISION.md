# Ramble — Product Vision

## What is this?

Voice-to-text capture. Tap, talk, get a transcript. That's it.

Ramble is an open-source iOS + watchOS app for capturing thoughts by voice. It records, transcribes, and stores everything locally. No accounts, no servers, no data leaving your device unless you tell it to.

## The Problem

Typing is slow. Thoughts are fast. By the time you open a notes app, half of what you wanted to say is gone — or you just don't bother.

Voice capture solves this, but existing solutions are unreliable, require setup, or lock your data into a platform. And none of them give you a clean way to pipe voice into your own tools.

## The North Star

> Quick tap → record → transcript appears → always findable. Nothing ever gets lost.

The app succeeds if:

- Recording starts in < 3 seconds from intent
- Transcription is fast and accurate
- The transcript log is easy to browse and copy from
- It works from phone and watch — wherever you are
- Nothing ever gets lost, even offline

## Core Loop

```
Have a thought → Tap record → Talk → Stop → Transcript appears
```

Later: Browse the log → Find what you said → Copy/paste it wherever you need it.

Or: Configure a webhook → Transcripts POST automatically to your agent, automation, or whatever you want.

## Who is this for?

Two audiences:

1. **Anyone who thinks faster than they type.** Capture ideas, notes, reminders, reflections by voice. No technical knowledge required. Works out of the box with Apple's on-device transcription.

2. **Technical users who want voice as an input to their own systems.** People running AI agents (OpenClaw, custom setups), automation pipelines, or personal knowledge bases. Configure a webhook URL, Ramble POSTs transcripts there. Fire and forget.

Both audiences share the same need: fast, reliable, private voice capture. What happens *after* capture is up to you.

## What Ramble is

A **voice input device** with a great UX. A dumb pipe that captures beautifully and gets out of your way.

- Records audio
- Transcribes it (on-device by default, or via your own API)
- Shows you a log of everything you've said
- Optionally sends transcripts to a webhook

That's the whole product.

## What Ramble is NOT

- **Not a note-taking app.** It captures voice and gives you text. What you do with it is your business.
- **Not an AI assistant.** No built-in LLM features. The webhook is the extensibility model. If you want AI, point the webhook at your agent.
- **Not a platform.** No accounts, no backend, no data stored anywhere except your device. The proof is in the codebase — it's open source.

## Transcription Strategy

**Default: Apple Speech (on-device).** Free, private, zero setup. Good enough for most people, and it keeps improving. This is the out-of-box experience.

**Optional: Custom transcription endpoint.** Point Ramble at any URL that accepts audio and returns text. Use Groq, Deepgram, Whisper, your own proxy — whatever you want. Same pattern as the webhook: just a URL in settings.

A reference Cloudflare Worker proxy will be provided for people who want to use third-party transcription APIs without putting API keys on device.

## Privacy

This is a core selling point, not just a feature.

- No login. No accounts. No analytics. No telemetry.
- All data stays on device.
- Open source — anyone can verify there's no backend.
- If you configure a webhook or proxy URL, *you* chose to send data there. Ramble doesn't send anything anywhere by default.

For privacy-minded users, the open source codebase is the proof. No trust required.

## Architecture

```
Record → Transcribe (on-device or custom endpoint) → Store locally → Optionally POST to webhook
```

### The trust contract: nothing ever gets lost

This is the single most important thing. If someone records a thought on their watch during a hike and the transcript isn't there when they get home, they'll never use the app again.

This means:
- **Persistent queues** — Every recording, transcription job, and webhook delivery is queued and retried until it succeeds or the user explicitly dismisses it.
- **Clear status everywhere** — Every recording shows its exact state at all times. No mystery spinners, no silent failures.
- **Transparent errors** — When something fails, say what failed and why. Offer a retry button.
- **Background processing** — Scheduled jobs to drain queues when the app isn't in the foreground.
- **Watch sync is solid** — Recordings made on the watch sync to the phone reliably. The queue is visible and nothing gets dropped.

### Key services

| Service | Role |
|---------|------|
| `AudioRecorderService` | 16kHz mono AAC capture |
| `TranscriptionQueueService` | Persistent job queue with retry |
| `AppleSpeechTranscriptionService` | On-device transcription (default) |
| `ProxyTranscriptionService` | HTTP client for custom transcription endpoints |
| `WebhookQueueService` | Independent queue for webhook delivery with retry |
| `BackgroundTaskService` | BGProcessingTask for background queue draining |
| `StorageService` | JSON file persistence |
| `PhoneConnectivityService` | WatchConnectivity bridge |

Full spec: `docs/spec-architecture.md`

## v1 Scope (App Store Release)

Ship the minimum that's **solid**, not the maximum that's possible.

### iOS app
- Record → transcribe → view transcript
- Browse/search transcript history
- Copy transcript text
- Settings: transcription provider (Apple Speech or custom URL), webhook URL

### Watch app
- Record from wrist
- Sync recordings to phone
- Queue status visible on watch

### What's NOT in v1
- CarPlay
- Widgets
- Siri integration
- Full-text search (just basic browsing for now)
- Any kind of organization features (tags, folders, etc.)

### Release plan
- Open source the repo on GitHub
- Release on App Store as a free utility
- Reference proxy implementation for custom transcription

## Design Principles

1. **Nothing ever gets lost.** Offline-first, persistent queues, clear status at all times. This is the core promise.

2. **Capture over organization.** Messy input beats no input. Structure comes later (and probably comes from whatever you pipe the webhook into, not from Ramble).

3. **No user data on servers.** Privacy by architecture. No login, no accounts, no server-side storage. Open source proves it.

4. **Pluggable, not opinionated.** Users choose their transcription provider. Webhook for downstream processing. Don't lock anyone in.

5. **Ship and iterate.** Don't overbuild. Use it, notice what's missing, add that. It's a free app — keep it simple.

## Open Questions

- How much transcript browsing/search UX is needed for v1 vs. "just scroll the list"?
- Should the webhook configuration support custom headers (for auth tokens)?
- Watch complication — worth it for v1?
