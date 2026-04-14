# Ramble

Voice capture that goes somewhere. Record a thought on the go, get an accurate transcript, and pipe it into your agent, workflow, or automation via webhook.

iPhone + Apple Watch. Open source, private by design, no accounts.

## Why Ramble

- **Best-in-class transcription** — Cloud models (Groq Whisper, Deepgram Nova-3, OpenAI GPT-4o Transcribe) or free on-device Apple Speech.
- **Webhook-native** — Every transcript can POST to any HTTPS endpoint. Signed requests, automatic retries.
- **Capture on the go** — Record from Apple Watch or phone. Walk, think, talk.
- **Private by architecture** — No accounts, no servers. Audio stays on-device unless you send it somewhere. Open source is the proof.

## What's in This Repo

| Directory | What it is |
|-----------|------------|
| `Ramble/` | iOS app (SwiftUI) |
| `watch Watch App/` | watchOS companion |
| `proxy/` | Cloudflare Worker transcription proxy |
| `website/` | Marketing site (Next.js static export) |

## Getting Started

Requires Xcode 26+. Clone, open `Ramble/Ramble.xcodeproj`, build and run. Works out of the box with Apple Speech — no API keys needed.

For cloud transcription, see `proxy/README.md`.

## Building from Command Line

```bash
# iOS app
xcodebuild -project Ramble/Ramble.xcodeproj -scheme Ramble \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'

# Watch app
xcodebuild -project Ramble/Ramble.xcodeproj -scheme "watch Watch App" \
  -destination 'platform=watchOS Simulator,name=Apple Watch Series 11 (46mm)'
```

## License

MIT
