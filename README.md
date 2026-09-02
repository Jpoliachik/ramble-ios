# Ramble

Voice capture that goes somewhere. Record a thought on the go, get an accurate transcript, and pipe it into your agent, workflow, or automation via webhook.

iPhone + Apple Watch. Open source, private by design, no accounts.

## Why Ramble

- **Best-in-class transcription** — Cloud models (Groq Whisper, Deepgram Nova-3, OpenAI GPT-Transcribe) or free on-device Apple Speech.
- **Webhook-native** — Every transcript can POST to any HTTPS endpoint. Signed requests, automatic retries.
- **Capture on the go** — Record from Apple Watch or phone. Walk, think, talk.
- **Private by architecture** — No accounts, no servers. Audio stays on-device unless you send it somewhere. Open source is the proof.

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

## Installing on Your Own Devices

Ramble is MIT licensed, so anyone can build it, but the bundle IDs in this repo are registered to the upstream team. To run it on your own iPhone and Apple Watch you need your own identifiers.

1. In Xcode, set **Team** to your own on every target (`Ramble`, `watch Watch App`, `RambleWidgets`, `RambleWatchWidgets`).
2. Change the bundle IDs to a namespace you control, keeping the prefix relationships intact, because iOS derives the app relationships from them:

   ```
   <your.prefix>.Ramble
   <your.prefix>.Ramble.watchkitapp
   <your.prefix>.Ramble.watchkitapp.widgets
   <your.prefix>.Ramble.widgets
   ```

   Also update `INFOPLIST_KEY_WKCompanionAppBundleIdentifier` on the watch target to match the phone app's ID.

Cloud transcription will not work on your build. App Attest is keyed to the app ID plus team, and the proxy verifies it server-side, so it rejects builds it doesn't know. Apple Speech, on-device Whisper, and webhooks all work normally.

### Installing without a debugger

If Xcode cannot mount the developer disk image on your watch (this happens whenever the watch runs a newer watchOS than your Xcode supports, `CoreDeviceError 12040`), you can still install. Archive, export an IPA, and install that instead: the installation service needs no DDI, only the debug service does.

```bash
xcodebuild -project Ramble/Ramble.xcodeproj -scheme Ramble \
  -destination 'generic/platform=iOS' -archivePath build/Ramble.xcarchive \
  -allowProvisioningUpdates archive

xcodebuild -exportArchive -archivePath build/Ramble.xcarchive \
  -exportPath build/export -exportOptionsPlist ExportOptions.plist \
  -allowProvisioningUpdates

xcrun devicectl device install app --device <iphone-udid> build/export/Ramble.ipa
```

`ExportOptions.plist` needs `method` = `debugging` (the Xcode 16+ name for a development export), `signingStyle` = `automatic`, and your `teamID`. Get the UDID from `xcrun devicectl list devices`.

**The watch app installs through the phone.** It is embedded in the phone IPA at `Payload/Ramble.app/Watch/`, and the iPhone pushes it to the paired watch. There is no separate watch install step, and none is possible without the DDI. If the watch app doesn't update, check the Watch app on your iPhone and toggle "Show App on Apple Watch" off and on.

You lose the debugger and console this way, which is why recordings carry an in-app activity log with timestamps for capture, transcription start, model load time, and completion.

### Two signing traps

**Bump the watch app's build number every time.** The watch app and its widget extension share a version, and the iPhone decides whether to re-push the watch app by comparing it. Leave `CURRENT_PROJECT_VERSION` unchanged and the watch silently keeps the old copy, including an old (or missing) complication. The extension's version must equal its containing watch app's version, or the build warns; note that this is the *watch app's* number, not the phone app's.

**"This app cannot be installed because its integrity could not be verified" on the watch** means an embedded extension is signed with a provisioning profile that doesn't list your watch. Xcode signs entitlement-free widget extensions with the team wildcard profile (`iOS Team Provisioning Profile: *`) rather than minting an explicit App ID, and a wildcard profile created before the watch was paired simply has no watch UDID in it. The phone installs fine, the watch refuses the whole bundle.

The fix is to force Xcode to fetch a fresh wildcard that includes every current device:

```bash
# Inspect what a built IPA actually embedded
security cms -D -i "Payload/Ramble.app/Watch/watch Watch App.app/PlugIns/RambleWatchWidgets.appex/embedded.mobileprovision" \
  | plutil -p - | grep -c "<watch-udid>"

# Delete the stale wildcard, then build once in Xcode (not xcodebuild) to refetch it
rm ~/Library/Developer/Xcode/UserData/Provisioning\ Profiles/<uuid>.mobileprovision
```

`xcodebuild -allowProvisioningUpdates` cannot do the refetch: without an Apple ID visible to the command line it fails with "No Accounts". The Xcode GUI can, so build there once and then go back to the command line. Check the embedded profiles in the IPA before installing rather than trusting the archive log.

## License

MIT
