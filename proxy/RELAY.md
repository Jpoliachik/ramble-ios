# Ramble Relay

The relay holds transcripts until your agent picks them up. You talk to your watch, Ramble transcribes on the phone, and the phone uploads the text here. Transcripts are temporary by design:

- **Picked up → deleted.** The text is deleted when the agent acks it.
- **Never picked up → deleted after 30 days** (`RETENTION_SECONDS`).
- **Audio never comes here.** Transcription happens before upload.

It runs in the same Cloudflare Worker as the [transcription proxy](README.md), with a small D1 database. The code is `src/relay.js`.

## What it stores

| What | Fields | Deleted when |
|---|---|---|
| Inbox | random id, hash of the app's inbox secret, created time | — |
| Pairing code | hash of the code, inbox id, expiry | used, replaced, or 10 minutes pass |
| Connection | random id, inbox id, hash of the agent's token, created and last-pull times | you tap Disconnect |
| Transcript | recording id, recorded-at time, duration, text, expiry (one copy per connected agent) | the agent acks it, you disconnect, you tap Delete everything, or 30 days pass |

No accounts, emails, names, IP addresses, or audio. Credentials are stored only as SHA-256 hashes.

## Authentication

| Who | Credential | Header |
|---|---|---|
| App | Inbox secret, from `POST /inboxes` (which needs App Attest) | `Authorization: Bearer rmbi_…` |
| Agent | Token from the pairing exchange | `Authorization: Bearer rmba_…` |

App Attest is checked once, when the phone creates its inbox, using the same scheme as `/transcribe`. Each credential works only on its own side.

## API

JSON bodies. Errors are `{"error": "..."}`.

### App

| Method | Path | Body → Response |
|---|---|---|
| `POST` | `/inboxes` | App Attest headers → `201 {"inbox_secret"}` |
| `POST` | `/inbox` | `{"recording_id", "created_at", "duration", "transcription"}` → `{"queued": <agents>}`. Idempotent on `recording_id`. |
| `DELETE` | `/inbox` | → `{"deleted": <n>}` |
| `POST` | `/pair/code` | → `201 {"code", "expires_at"}`. A new code replaces the old one. |
| `GET` | `/connections` | → `{"connections": [{"id", "created_at", "last_pull_at", "pending"}]}` |
| `DELETE` | `/connections/:id` | → `{"status": "disconnected"}` |

### Agent

| Method | Path | Body → Response |
|---|---|---|
| `POST` | `/pair/exchange` | `{"code": "K7QX-MP4D"}`, no auth → `201 {"token"}` |
| `GET` | `/inbox` | → `{"items": [{"id", "recording_id", "created_at", "duration", "transcription"}], "has_more"}`. Oldest first, up to 50. |
| `POST` | `/inbox/ack` | `{"ids": [41, 42]}` → `{"deleted": <n>}`. Up to 500 ids. |

Codes are case-insensitive and ignore spaces and dashes. Unacked items come back on every pull, so if `has_more` is true, ack and pull again. A `401` on a pull means the user disconnected.

## Agent instructions

Paste this into your agent:

> I use Ramble to record thoughts on my Apple Watch. Ramble transcribes them and holds them at `https://ramble-transcription-proxy.jpoliachik.workers.dev` until you pick them up.
>
> 1. When I give you a Ramble pairing code (like `K7QX-MP4D`), send `POST https://ramble-transcription-proxy.jpoliachik.workers.dev/pair/exchange` with `{"code": "<the code>"}`. Save the returned `token` as a secret. Don't repeat it in chat. Codes expire after 10 minutes; if it fails, ask me for a new one.
> 2. Check for new transcripts as often as you can, using whatever way of running recurring work suits you best. Each check is a tiny request that usually returns an empty list, so frequent checks are fine. To check, `GET https://ramble-transcription-proxy.jpoliachik.workers.dev/inbox` with `Authorization: Bearer <token>`. Handle each item's `transcription` as if I'd sent it to you directly. Then `POST https://ramble-transcription-proxy.jpoliachik.workers.dev/inbox/ack` with `{"ids": [...]}` for the items you handled. If `has_more` is true, pull again.
> 3. If a request returns 401, I disconnected you. Stop checking and tell me.

To test: record "Test, remind me to water the plants" on the watch. Settings shows one waiting for the agent. After its next check the count drops to 0.

## Setup

1. `npx wrangler d1 create ramble-relay`
2. Uncomment the `[[d1_databases]]` block in `wrangler.toml` and paste the id.
3. `npx wrangler d1 migrations apply ramble-relay --remote`
4. `npx wrangler deploy`

Until the D1 binding exists, relay routes answer `503` and transcription works as before. A cron every 15 minutes deletes expired rows.

App Attest can't run in the simulator. For simulator testing, run the relay locally (below) with `DEV_BYPASS_TOKEN` in `.dev.vars`, and enter the same value as the server bypass key in the app's debug sheet (tap the version number in Settings), where you can also point the relay URL at `wrangler dev`. The key is sent as `X-Dev-Bypass`.

If `DEV_BYPASS_TOKEN` is set on the deployed Worker, anyone holding it skips App Attest for both `/inboxes` and `/transcribe`. Leave it unset in production, or make it long and random and never share it.

### Local

```bash
echo 'DEV_BYPASS_TOKEN="dev"' > .dev.vars
npx wrangler d1 migrations apply ramble-relay --local
npx wrangler dev                               # uses a local copy of the database
```

## Tests

`npm test` runs every endpoint against the real schema, with Node's SQLite standing in for D1.
