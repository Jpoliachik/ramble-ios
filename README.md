# Ramble

Voice in, webhooks out. Record a thought on iPhone or Apple Watch, get an accurate transcript, and POST it straight to your own stack — your AI agent, n8n, Node-RED, Home Assistant, Zapier, or any HTTPS endpoint.

iPhone + Apple Watch. MIT-licensed, private by design, no account, no cloud required.

## Why Ramble

- **Your voice, your endpoint** — Every transcript can POST to any HTTPS webhook. Send it to your own server, n8n, Node-RED, Home Assistant, an AI agent, or your backend. Signed requests, automatic retries.
- **Free core, no account** — On-device transcription (Apple Speech) and webhook delivery are free forever. No login, nothing stored on our servers.
- **Best-in-class transcription** — Optional cloud models (Groq Whisper, Deepgram Nova-3, OpenAI GPT-4o Transcribe) for $3.99/mo when you want top accuracy.
- **Capture on the go** — Record from Apple Watch or phone, no screen needed. Walk, think, talk.
- **Open source is the proof** — MIT-licensed, audit it yourself. Audio stays on-device unless you choose to send it somewhere.

## What's in This Repo

| dir                |                                                                                             |
| ------------------ | ------------------------------------------------------------------------------------------- |
| `Ramble/`          | iOS app (SwiftUI)                                                                           |
| `watch Watch App/` | watchOS companion                                                                           |
| `proxy/`           | Cloudflare Worker transcription proxy                                                       |
| `website/`         | Marketing site - [goodloop.dev/ramble](https://goodloop.dev/ramble) (Next.js static export) |

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
