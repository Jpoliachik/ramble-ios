# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Ramble** is a personal voice journaling iOS app for Justin. Core flow: voice recording → transcription → LLM extraction → searchable archive. The goal is frictionless daily capture (< 3 seconds from intent to talking) that builds a rich, searchable record of thoughts and activities.

### Key Principles

- **For Justin only** — Optimize for one person's workflow, not generic "users"
- **Capture over organization** — Messy input beats no input; structure comes later
- **LLM-native** — Design data formats assuming LLMs will process them
- **Plain text wins** — Markdown files, no proprietary formats or complex databases
- **Don't overbuild** — Ship minimal, use it, iterate based on real use

See `docs/VISION.md` for full product vision and iteration phases.

## Build & Development

This is a native iOS project using Xcode. No CocoaPods or SPM dependencies.

```bash
# Open in Xcode
open Ramble/Ramble.xcodeproj

# Build from command line
xcodebuild -project Ramble/Ramble.xcodeproj -scheme Ramble -destination 'platform=iOS Simulator,name=iPhone 16'

# Build and run tests (when tests exist)
xcodebuild test -project Ramble/Ramble.xcodeproj -scheme Ramble -destination 'platform=iOS Simulator,name=iPhone 16'
```

## Architecture

### Targets

- **Ramble** — Main iOS app (SwiftUI)
- **widgetsExtension** — WidgetKit extension with Live Activities support
- **watch Watch App** — watchOS companion app

### Source Layout

```
Ramble/
├── Ramble/           # Main iOS app source
├── widgets/          # Widget extension (WidgetKit + ActivityKit)
├── watch Watch App/  # watchOS companion
└── Ramble.xcodeproj/
```

### Tech Stack

- SwiftUI for all UI
- WidgetKit for home screen widgets
- ActivityKit for Live Activities / Dynamic Island
- Deployment target: iOS 26.2, watchOS 26.2

## Current Phase

**Phase 1: Capture** — Building the recording → transcription → extraction flow. Focus on making it fast and reliable enough for daily use.
