# Ramble

Voice capture for Apple Watch and iPhone. Record a thought on the go, get an accurate transcript, and send it to your agent, workflow, or automation by webhook.

No accounts. The relay transcribes and passes notes along; it's a relay, not an archive. Site: [ramble.watch](https://ramble.watch).

## What's in This Repo

| dir                       |                                                                                  |
| ------------------------- | -------------------------------------------------------------------------------- |
| `Ramble/Ramble/`          | iOS app (SwiftUI)                                                                |
| `Ramble/watch Watch App/` | watchOS companion                                                                |
| `proxy/`                  | Cloudflare Worker: transcription and agent relay (`proxy/README.md`, `RELAY.md`) |
| `website/`                | Marketing site and docs, [ramble.watch](https://ramble.watch) (Next.js export)   |
| `specs/`                  | What Ramble does, the source of truth for behavior                               |
| `docs/`                   | Brand, design, App Store copy, sync architecture, webhook API                    |
| `images/appstore/`        | Current App Store art                                                            |

## Getting Started

Requires Xcode 26+. Open `Ramble/Ramble.xcodeproj`, then build and run. Debug simulator builds talk to a local relay at `http://localhost:8787`; see `proxy/README.md` to run one.

## Building from Command Line

```bash
# iOS app
xcodebuild -project Ramble/Ramble.xcodeproj -scheme Ramble \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'

# Watch app
xcodebuild -project Ramble/Ramble.xcodeproj -scheme "watch Watch App" \
  -destination 'platform=watchOS Simulator,name=Apple Watch Series 11 (46mm)'

# Relay tests
cd proxy && npm ci && npm test
```

## License

MIT
