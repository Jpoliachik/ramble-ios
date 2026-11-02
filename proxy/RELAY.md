# Ramble Relay

The relay moves transcripts from Ramble to your agent. You talk to your watch, Ramble transcribes on the phone, and the relay holds the text until your agent picks it up. Transcripts here are temporary by design:

- **Picked up → deleted.** The text is deleted the moment the agent acknowledges it.
- **Never picked up → deleted after 30 days.** Long enough to ride out an agent outage, then gone.
- **Audio never comes here.** Transcription happens on the phone first. On-device Apple Speech touches no server at all.

It runs in the same Cloudflare Worker as the [transcription proxy](README.md), under its own routes, with a small D1 database. The code is `src/relay.js`.

## What it stores

This is the whole list:

| What | Fields | Deleted when |
|---|---|---|
| Inbox | random id, hash of the app's inbox secret, created time | — |
| Pairing code | hash of the code, inbox id, agent type, expiry | used, replaced, or 10 minutes pass |
| Connection | random id, inbox id, agent type, hash of the agent's token, created and last-pull times | you tap Disconnect |
| Queued transcript | recording id, recorded-at time, duration, text, expiry — one copy per connected agent | text: when the agent acks it, you disconnect, you tap Delete everything, or 30 days pass unclaimed |
| Pickup receipt | the same row after ack, with the text removed: recording id, pickup time | 24 hours after pickup |

There are no accounts, emails, names, IP addresses, or audio. Audio never reaches the relay: transcription happens before upload, and on-device Apple Speech touches no server at all. Credentials are stored only as SHA-256 hashes. Logs record counts and ids, never transcript text.

We identify inboxes, not people.

## How it works

```
Watch ──► iPhone (transcribe) ──POST /inbox──► relay ──GET /inbox──► agent
                                                 ▲                      │
                                                 └──POST /inbox/ack─────┘ (text deleted)
```

1. **Inbox.** When you turn the relay on, the app creates an inbox (`POST /inboxes`, App Attest required) and keeps the returned inbox secret in the Keychain.
2. **Pairing.** Settings → Connect agent shows a short code like `K7QX-MP4D`. You tell your agent "I downloaded Ramble, connect it" and paste the code. The agent exchanges it once for a long-lived token (`POST /pair/exchange`). This is the same shape as OAuth's device authorization grant: the code is single-use and dies in 10 minutes, so pasting it in chat is safe. The token goes in the agent's secret storage and never appears in chat.
3. **Upload.** Each transcript is uploaded once (`POST /inbox`) and copied into one queue per connected agent. If Muse acks first, ChatGPT's copy is untouched.
4. **Pull and ack.** The agent pulls on a schedule (`GET /inbox`), handles each transcript, then acks (`POST /inbox/ack`), which deletes the text immediately. A text-free receipt stays 24 hours so the phone can show "Picked up by Muse" (`GET /receipts`).
5. **Expiry.** Anything not picked up within 30 days disappears from pulls the moment it expires. A cron job every 15 minutes deletes expired rows from disk.
6. **Disconnect.** Tapping Disconnect (`DELETE /connections/:id`) kills the token and deletes its queue. Delete everything now (`DELETE /inbox`) empties every queue.

## Authentication

| Direction | Credential | Header |
|---|---|---|
| App → relay | Inbox secret. Creating the inbox also needs an App Attest assertion. | `Authorization: Bearer rmbi_…` (and `X-App-Attest-Key-Id`, `X-App-Attest` on `POST /inboxes`) |
| Agent → relay | Connection token from the pairing exchange | `Authorization: Bearer rmba_…` |

App Attest is checked once, when the phone creates its inbox. That proves the inbox belongs to a real copy of Ramble on a real Apple device. It uses the same scheme and storage as `/transcribe` (see [App Attest Implementation Notes](README.md#app-attest-implementation-notes)), so a device that attested for cloud transcription doesn't attest again.

Everything after that needs only the inbox secret: uploads, pairing codes, listing connections, Disconnect, and Delete everything. Delivery and the kill switches keep working even if attestation is having a bad day.

Each credential works only on its own side: an agent token can't upload or manage connections, and the inbox secret can't pull.

## API

All bodies are JSON. Errors are `{"error": "..."}` with a 4xx/5xx status.

### App-facing

| Method | Path | Auth | Body → Response |
|---|---|---|---|
| `POST` | `/inboxes` | App Attest | — → `201 {"inbox_id", "inbox_secret"}` (secret is returned once) |
| `POST` | `/inbox` | inbox secret | `{"recording_id", "created_at", "duration", "transcription"}` → `{"queued": <agents>, "expires_at"}` |
| `DELETE` | `/inbox[?connection_id=]` | inbox secret | — → `{"deleted": <n>}` |
| `POST` | `/pair/code` | inbox secret | `{"agent_type": "muse" \| "chatgpt" \| "grok" \| "claude" \| "other"}` → `201 {"code", "agent_type", "expires_at"}` |
| `GET` | `/connections` | inbox secret | — → `{"connections": [{"id", "agent_type", "created_at", "last_pull_at", "pending"}]}` |
| `DELETE` | `/connections/:id` | inbox secret | — → `{"status": "revoked"}` |
| `GET` | `/receipts` | inbox secret | — → `{"receipts": [{"recording_id", "connection_id", "agent_type", "picked_up_at"}]}` (last 24 hours, no text) |

The upload body uses the same field names as the [webhook payload](../docs/webhook-api.md). Uploads are idempotent on `recording_id`, so the app's retry queue can resend safely. Issuing a new pairing code cancels the previous one. An inbox can have up to 10 connected agents.

### Agent-facing

**Exchange a pairing code** — no auth; the code is the credential.

```http
POST /pair/exchange
{"code": "K7QX-MP4D"}
```

```json
{"token": "rmba_…", "connection_id": "con_…", "agent_type": "muse", "unacked_retention_seconds": 2592000}
```

Codes are case-insensitive and ignore spaces and dashes.

**Pull new transcripts**

```http
GET /inbox?since=<id>&limit=<n>
Authorization: Bearer rmba_…
```

```json
{
  "items": [
    {
      "id": 41,
      "recording_id": "6F1C2C1E-…",
      "created_at": "2026-11-01T19:00:00Z",
      "duration": 8.2,
      "transcription": "Remind me to book the dentist.",
      "expires_at": "2026-11-02T19:00:05Z"
    }
  ],
  "next_since": 41,
  "has_more": false
}
```

Oldest first. `limit` defaults to 50, max 100. `since` is optional: the relay keeps no cursor, and unacked items stay put, so pulling without `since` simply returns everything still waiting. Pass `next_since` back to page through a backlog.

**Acknowledge**

```http
POST /inbox/ack
Authorization: Bearer rmba_…
{"ids": [41]}
```

```json
{"acknowledged": 1}
```

Deletes the text of those items now. Up to 500 ids per call. Ack only after the agent has durably handled the item; an unacked item is retried on the next pull until it expires.

The Worker's `/health`, `/attest/challenge`, and `/attest` endpoints serve the relay too.

## For agents

The loop is small enough to describe to any agent that can make HTTP requests and keep a secret:

1. When the user says "I downloaded Ramble, connect it" and gives a code, `POST /pair/exchange` with it. Save `token` in secret storage. Don't repeat it back in chat.
2. On a schedule (every 15 minutes is a reasonable default), `GET /inbox` with the token.
3. For each item, do what the user asked in `transcription`. Use `recording_id` to skip anything already handled.
4. `POST /inbox/ack` with the ids you handled.
5. If a pull returns `401`, the user disconnected. Stop polling and tell them.

## Setting up the relay

The relay deploys with the proxy. On an existing proxy deployment:

1. Create the database:
   ```bash
   npx wrangler d1 create ramble-relay
   ```
2. In `wrangler.toml`, uncomment the `[[d1_databases]]` block and paste the id.
3. Apply the schema:
   ```bash
   npx wrangler d1 migrations apply ramble-relay --remote
   ```
4. Retention is set by `UNACKED_RETENTION_SECONDS` (default 2592000, 30 days) and `RECEIPT_RETENTION_SECONDS` (default 86400, 24 hours) under `[vars]`.
5. `npx wrangler deploy`

Until the D1 binding exists, relay routes answer `503` and transcription works as before.

App Attest only works from a real device running a copy of Ramble whose bundle ID matches. For simulator testing, `npx wrangler secret put DEV_BYPASS_TOKEN` and send it as `X-Dev-Bypass`. Leave it unset in production.

In the app, the debug sheet (tap the version number in Settings) has a relay URL override for pointing at a test deployment.

### Local development

```bash
cp wrangler.toml wrangler.local.toml          # uncomment the D1 block; any id works locally
echo 'DEV_BYPASS_TOKEN="dev"' > .dev.vars
npx wrangler d1 migrations apply ramble-relay --local -c wrangler.local.toml
npx wrangler dev -c wrangler.local.toml
```

## Tests

```bash
npm test
```

The relay tests run every endpoint against the real schema, using Node's built-in SQLite in place of D1. App Attest is stubbed because it needs a real device. CI runs them with the proxy's tests on every PR touching `proxy/`.
