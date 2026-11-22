# Ramble

**Say it. Let it go.** Ramble is a voice capture app for Apple Watch and iPhone. Say a thought to your watch, get back to what you were doing, and your agent picks it up later. No accounts, no reply to wait for.

[App Store](https://apps.apple.com/app/id6761857751) · [ramble.watch](https://ramble.watch) · [Connect your agent](https://ramble.watch/docs)

## Privacy, in the code

Ramble's server is a relay, not an archive. Your audio is sent to a transcription provider and deleted as soon as the transcript is ready. Transcripts are deleted when your agent picks them up, or after 30 days. Your full history lives only on your iPhone.

Ramble also keeps basic usage stats for each note, like its length and whether it came from your watch or iPhone, under a random ID. Never your audio or your words.

The relay is in [`proxy/`](proxy/): what it stores is listed in [`proxy/README.md`](proxy/README.md), and the behavior it promises is in [`specs/`](specs/README.md).

## What's here

| Path | What |
| --- | --- |
| `Ramble/` | The iPhone app, the watch app and the watch control (SwiftUI) |
| `proxy/` | The relay: a Cloudflare Worker that takes uploads, transcribes, and holds transcripts for your devices and agents ([API](proxy/RELAY.md)) |
| `plugins/ramble/` | The Claude plugin: the Ramble connector plus a skill for working through notes |
| `admin/` | The operator's read-only dashboard (counts only, never anyone's words) |
| `website/` | [ramble.watch](https://ramble.watch) (Next.js static export) |
| `specs/` | What Ramble does, requirement by requirement. The code must match them |
| `docs/` | Why and how: brand, design, sync architecture, webhooks, operations |

## Connect an agent

Any agent that can make an HTTPS request can pull notes; see [ramble.watch/docs](https://ramble.watch/docs) and [`proxy/RELAY.md`](proxy/RELAY.md). MCP clients such as Claude connect at `https://api.ramble.watch/mcp` ([`specs/connector.md`](specs/connector.md)).

## Build

Requires Xcode 26+. Open `Ramble/Ramble.xcodeproj`. Debug simulator builds talk to a local relay at `http://localhost:8787`; see "Local Development" in [`proxy/README.md`](proxy/README.md).

```bash
cd proxy && npm ci && npm test     # relay tests, no credentials needed
cd website && npm install && npm run dev
```

## License

The source is public so it can be read and checked. It is not open source: no licence is granted, and all rights are reserved by Good Loop Software LLC. Questions: support@ramble.watch.
