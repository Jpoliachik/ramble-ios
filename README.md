# Ramble

Voice capture that goes somewhere. Record a thought on the go, get an accurate transcript, and pipe it into your agent, workflow, or automation via webhook.

iPhone + Apple Watch. Open source, private by design, no accounts.

## Why Ramble

**Best-in-class transcription** — Choose from the latest cloud models (Groq Whisper, Deepgram Nova-3, OpenAI GPT-4o Transcribe) or use Apple's on-device speech recognition for free. New models get added as they ship.

**Webhook-native** — Every transcript can automatically POST to any HTTPS endpoint. Connect Ramble to an AI agent, a Zapier workflow, a Notion database, or your own backend. Signed requests, automatic retries.

**Capture on the go** — Record from your Apple Watch or phone without looking at a screen. Walk, think, talk. Your transcript is waiting when you get back.

**Private by architecture** — No accounts. No login. No user data on our servers. Audio and transcriptions never leave your device unless you choose to send them somewhere. Open source — the codebase is the proof.

## Getting Started

### Prerequisites

- Xcode 26+
- iOS 26+ / watchOS 11+ device or simulator

### Setup

1. Clone the repo:
   ```bash
   git clone https://github.com/justinpoliachik/ramble-ios.git
   cd ramble-ios
   ```

2. Open in Xcode:
   ```bash
   open Ramble/Ramble.xcodeproj
   ```

3. Build and run. Works out of the box with Apple Speech transcription — no API keys, no config.

### Cloud Transcription (Optional)

Cloud transcription routes through a thin Cloudflare Worker proxy (`proxy/`) — it forwards audio to the transcription provider and returns text. Stores nothing. The proxy code is in this repo so you can verify exactly what it does. See `proxy/README.md` for setup.

## Project Structure

- `Ramble/` — iOS app (SwiftUI)
- `watch Watch App/` — watchOS companion
- `proxy/` — Cloudflare Worker transcription proxy
- `website/` — Marketing site (Next.js static export)

## Building from Command Line

```bash
# Build iOS app
xcodebuild -project Ramble/Ramble.xcodeproj -scheme Ramble -destination 'platform=iOS Simulator,name=iPhone 17 Pro'

# Build watch app
xcodebuild -project Ramble/Ramble.xcodeproj -scheme "watch Watch App" -destination 'platform=watchOS Simulator,name=Apple Watch Series 11 (46mm)'
```

## License

MIT
