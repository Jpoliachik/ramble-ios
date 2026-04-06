# Ramble

An open-source voice-to-text capture app for iOS + watchOS. Tap record, talk, get a transcript. That's the whole thing.

**Core flow:** Record → Transcribe locally (Apple Speech) → Browse/copy transcripts

No accounts, no servers, no data leaving your device unless you tell it to. Open source — the codebase is the proof.

## Setup

### Prerequisites

- Xcode 16+
- iOS 18+ / watchOS 11+ device or simulator

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

3. Build and run on a simulator or device. Works out of the box with Apple Speech transcription.

## Project Structure

```
Ramble/
├── Ramble/              # Main iOS app (SwiftUI)
│   ├── Models/          # Data models (Recording, Settings)
│   ├── Services/        # Audio, transcription, storage, sync
│   ├── ViewModels/      # Recording and settings view models
│   ├── Views/           # SwiftUI views
│   └── Utilities/       # Haptics, constants
└── watch Watch App/     # watchOS companion app
```

## Building from Command Line

```bash
# Build iOS app
xcodebuild -project Ramble/Ramble.xcodeproj -scheme Ramble -destination 'platform=iOS Simulator,name=iPhone 17 Pro'

# Build watch app
xcodebuild -project Ramble/Ramble.xcodeproj -scheme "watch Watch App" -destination 'platform=watchOS Simulator,name=Apple Watch Series 11 (46mm)'
```

## Transcription

**Default:** Apple Speech (on-device). Free, private, zero setup.

**Optional:** Point Ramble at a custom transcription endpoint for higher-quality models. A reference Cloudflare Worker proxy is included in `proxy/` — it forwards audio to Groq Whisper and returns text. See `proxy/README.md` for setup.

**Webhook:** Optionally POST transcripts to any URL for downstream processing (agents, automations, etc.). Configure in Settings.

## License

MIT
