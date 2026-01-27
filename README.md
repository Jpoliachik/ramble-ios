# Ramble

A personal voice journaling iOS app. Record your thoughts, get them transcribed and extracted by LLMs, and build a searchable archive of your life.

**Core flow:** Voice recording → Transcription (Groq) → LLM extraction → Searchable archive

The goal is frictionless daily capture — under 3 seconds from intent to talking.

## Setup

### Prerequisites

- Xcode 16+
- iOS 18+ / watchOS 11+ device or simulator
- A [Groq API key](https://console.groq.com/) (free tier works)

### Getting Started

1. Clone the repo:
   ```bash
   git clone https://github.com/justinpoliachik/ramble-ios.git
   cd ramble-ios
   ```

2. Create your secrets file:
   ```bash
   cp Ramble/Ramble/Secrets.example.swift Ramble/Ramble/Secrets.swift
   ```

3. Open `Ramble/Ramble/Secrets.swift` and replace `YOUR_GROQ_API_KEY_HERE` with your Groq API key.

4. Open and run in Xcode:
   ```bash
   open Ramble/Ramble.xcodeproj
   ```

5. Build and run on a simulator or device.

### Optional: Webhook

Ramble can send transcription data to a webhook URL for further processing (e.g. saving to Obsidian, triggering automations). Configure the webhook URL and auth token in the app's Settings screen.

## Project Structure

```
Ramble/
├── Ramble/              # Main iOS app (SwiftUI)
│   ├── Models/          # Data models (Recording, Settings)
│   ├── Services/        # Audio, transcription, storage, webhook
│   ├── ViewModels/      # Recording and settings view models
│   ├── Views/           # SwiftUI views
│   └── Utilities/       # Haptics, constants
├── widgets/             # WidgetKit extension with Live Activities
└── watch Watch App/     # watchOS companion app
```

## Building from Command Line

```bash
# Build
xcodebuild -project Ramble/Ramble.xcodeproj -scheme Ramble -destination 'platform=iOS Simulator,name=iPhone 16'

# Run tests
xcodebuild test -project Ramble/Ramble.xcodeproj -scheme Ramble -destination 'platform=iOS Simulator,name=iPhone 16'
```

## License

MIT
