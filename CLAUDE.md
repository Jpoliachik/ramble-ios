# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Ramble** is a voice capture app for Apple Watch + iPhone. Record your thoughts on the go, get accurate transcripts, and pipe them into your agent, workflow, or automation via webhook. No accounts; the server is a relay, not an archive.

For full brand positioning, audience, tone, and messaging guidelines, see **`docs/brand.md`**.

For design philosophy and the design system (color, type, spacing, motion, haptics), see **`docs/design.md`**. Read it before any UI work on the watch, iPhone, or website.

## Specs: the source of truth for behavior

**`specs/` describes what Ramble does right now. The code MUST match the specs at all times.** Read `specs/README.md` for what a spec is, its format, and the index of spec files. `docs/` explains why and how; `specs/` states what.

These rules are not optional. They apply to every change, however small:

1. **Read first.** Before changing anything a person, an agent, or another system can observe, read the spec for that area.
2. **Update the spec in the same commit.** Any change to observable behavior MUST update the affected spec in the same commit as the code. A behavior change without its spec update is not done, and must not be pushed.
3. **New behavior gets a requirement.** A new feature adds requirements and scenarios to the right spec. If a spec passes about 300 lines, split it and update the index in `specs/README.md`.
4. **Removed behavior leaves the spec.** Deleting a feature deletes its requirements.
5. **A mismatch is a bug.** If code and spec disagree and you weren't asked to change that behavior, do not quietly rewrite the spec to match the code, or the code to match the spec. Tell Justin which one looks wrong and let him decide.
6. **Refactors don't touch specs.** If behavior is unchanged, the spec is unchanged.
7. **Specs describe the present only.** No history, change logs, plans, or TODOs in specs. Plans go in a thread or in `docs/`.
8. **Report it.** When you finish a task, say which specs you updated, or say "No spec change" with the reason.

### Release plan

- Free download: 25 notes free, then a $14.99 one-time unlock, no subscription (`specs/purchase.md`)
- Cloud transcription only (Groq Whisper v3 Turbo, retried server-side when Groq is down) via the Cloudflare Worker relay
- Marketing website on Vercel at https://ramble.watch (source in `website/`, static export)
- **App Store URL:** https://apps.apple.com/app/id6761857751 (Apple ID: 6761857751)

## Pull requests: safe to merge?

Whenever you open a PR, run the `pr-review` skill (`.claude/skills/pr-review/SKILL.md`) once CI has finished, and lead your reply with its verdict. It sends the diff to a small panel of expert reviewers (deploy and ops, security, agent integrations, and a pass on whether the change stays true to Ramble's core values in `docs/brand.md` and `docs/design.md`), only those the diff touches, and rolls them up into one answer. Run it again when Justin asks whether a PR is safe to merge. Small changes still go straight to `main` without a PR.

## Build & Development

This is a native iOS project using Xcode. No CocoaPods or SPM dependencies.

```bash
# Open in Xcode
open Ramble/Ramble.xcodeproj

# Build iOS app
xcodebuild -project Ramble/Ramble.xcodeproj -scheme Ramble -destination 'platform=iOS Simulator,name=iPhone 17 Pro'

# Build watch app
xcodebuild -project Ramble/Ramble.xcodeproj -scheme "watch Watch App" -destination 'platform=watchOS Simulator,name=Apple Watch Series 11 (46mm)'
```

### Proxy

```bash
cd proxy
npm ci
npm test         # Relay API, pipeline, providers, Apple verification, rate limits
npm run dev      # Local Worker via wrangler
```

Tests need no credentials or Worker runtime: they run the Worker's request
handler against a SQLite stand-in for D1 and fakes for R2, providers and Apple
(`test/harness.js`, `test/d1.js`). CI runs them on every PR touching
`proxy/**` and gates the deploy on them. Bindings, secrets and vars are listed
in `proxy/README.md`.

There is no staging relay. Testing is local (`npm test`, and `npm run dev`,
which runs the same Worker as production with local D1/R2/KV) plus TestFlight
against production. Debug simulator builds talk to `http://localhost:8787` and
skip App Attest with a key that only a local relay accepts (`.dev.vars`), in one
central check on `POST /inboxes`. Never add per-endpoint dev paths or a bypass
that production could honor; new endpoints work locally automatically.

### Website

```bash
cd website
npm install
npm run build    # Static export to website/out/
npm run dev      # Dev server at localhost:3000
```

The site is a static export (`output: "export"`) deployed on Vercel from the `website/` root directory, with a preview deployment for every PR that touches it. It is served from the root of Ramble's own domain, https://ramble.watch, so there is no `basePath`.

**Pages:** Landing (`/`), Privacy Policy (`/privacy`), Terms of Use (`/terms`), Support (`/support`), Connect your agent + relay API (`/docs`), Webhook API Docs (`/docs/webhooks`), Requirements + troubleshooting (`/docs/help`)

## Architecture

### Targets

- **Ramble** — Main iOS app (SwiftUI)
- **watch Watch App** — watchOS companion app
- **RambleWatchControls** — widget extension embedded in the watch app: the "Ramble" control (Action button, Control Center, Smart Stack). watchOS 26+ only

### Source Layout

```
Ramble/
├── Ramble/            # Main iOS app source
├── watch Watch App/   # watchOS companion
└── Ramble.xcodeproj/
website/               # Marketing site (Next.js static export)
proxy/                 # Cloudflare Worker: transcription proxy + agent relay (RELAY.md)
admin/                 # Cloudflare Worker: Justin's private admin dashboard (README.md)
plugins/ramble/        # Claude plugin: the MCP connector + the ramble-notes skill (specs/connector.md)
```

### Data Flow

1. **Record** — watch or iPhone captures 16kHz mono AAC (60-minute cap)
2. **Upload** — each device uploads its own notes straight to the relay with `PUT /notes/:id` (watch: background URLSession with a phone-minted watch token; phone: inbox secret). The note ID is the idempotency key.
3. **Transcribe** — the relay stores audio in R2, transcribes (Groq Whisper v3 Turbo, retried for up to 20 hours if Groq is down), deletes the audio, and copies the transcript to each eligible agent
4. **History** — the phone pulls transcripts with `GET /notes` and acks them; watch notes merge by ID with details and audio sent over WatchConnectivity
5. **Webhook** — optional POST from the phone once it has the transcript

WatchConnectivity now carries only the watch token and account state (phone → watch), note details and "needs a connection" (watch → phone), and best-effort audio for playback. See **`docs/sync-architecture.md`** for the Apple APIs at each hop and their limits; read it before changing the watch → relay or watch → phone path.

### Key Services

| Service | Role |
| --- | --- |
| `UploadQueueService` (phone) | Uploads phone notes, handles holds, refusals, retries and hand retries |
| `NoteSyncService` (phone) | Check-in: settings, `GET /notes` + ack, delivery status, account |
| `RelayService` (phone) | Relay HTTP client, inbox creation (App Attest), watch token |
| `AccountService` (phone) | Last known free notes / unlock |
| `PurchaseService` (phone) | StoreKit 2 unlock, restore, early-buyer proofs |
| `PhoneConnectivityService` (phone) | WatchConnectivity: application context, note details, audio |
| `WebhookQueueService` (phone) | Webhook delivery with retry |
| `BackgroundTaskService` (phone) | Background check-ins and uploads |
| `WatchRelayService` (watch) | Upload, status polling, holds and their release |
| `WatchConnectivityService` (watch) | Watch side of the WatchConnectivity contract |
| `WatchNoteStore` (watch) | Persisted watch notes and audio retention |

### Models

- `Recording` (phone) — a note: id, createdAt, duration, source, audio, server status and result, transcript, delivery and webhook state
- `WatchNote` (watch) — a watch note: upload state, holds, server status, first line, audio kept until safe
- `RelayAccount` — `GET /account`: unlocked, free notes
- `WebhookJob` — webhook delivery job with retry

### Tech Stack

- SwiftUI for all UI
- Deployment target: iOS 18.6, watchOS 10.0 (covers Series 4+ and first-gen SE; guard newer watch APIs with `#available`). If you change a deployment target, update `MIN_IOS`/`MIN_WATCHOS` in `website/src/lib/site.ts` and the requirements in `website/public/llms*.txt`

### Admin

Operator-only tools live in `admin/`, a separate Worker at https://ramble-admin.jpoliachik.workers.dev, never in the relay. Cloudflare Access signs Justin in (email code) and lets agents in with service tokens; the Worker also verifies the Access JWT on every request. Read-only, counts and labels only, every page has a JSON twin. Spec: `specs/admin.md`. Setup and the pattern for adding tools: `admin/README.md`.

### Relay API

The full contract is **`specs/relay-api.md`**; agent-facing docs are `proxy/RELAY.md` and `/docs`. In short: the phone creates an inbox once with an App Attest assertion and gets an inbox secret (`rmbi_`); it mints an upload-only watch token (`rmbw_`); agents pair with a one-time code for an agent key (`rmba_`). MCP clients such as Claude connect at `/mcp` with OAuth whose sign-in page takes the same code and whose access token is an agent key (`specs/connector.md`, `src/oauth.js`, `src/mcp.js`). Audio lives in R2 only until transcribed; transcripts for the person's devices and agent copies are deleted on ack or after 30 days. Purchases are verified server-side against Apple's root CA (`src/apple.js`).

### Transcription

One provider and model for everyone: Groq Whisper v3 Turbo. There is no fallback provider: when Groq is overloaded or down, the note waits and is retried for up to 20 hours (`specs/transcription.md`). There is no model picker. Don't claim a model is best for noise or accents: no independent benchmark backs that.

## Resolved Questions

- **Transcript browsing UX for v1:** Just scroll the list. No search, no tags, no folders.
- **Watch complication:** Not in v1.
- **Pricing:** Free download, 25 notes free, then $14.99 once. No usage limit. Heavy use is monitored internally: one operator alert per user per month past an internal threshold, and a manual per-user suspend switch (`docs/operations.md`). The threshold lives only in the `HEAVY_USE_HOURS` secret (relay and admin Workers). This repo is public, so never write the figure anywhere in it, and never show it to people. Early $4.99 buyers and active subscribers are unlocked (`specs/purchase.md`).
- **Platform:** Apple only (iPhone + Apple Watch). No Android, no web.
