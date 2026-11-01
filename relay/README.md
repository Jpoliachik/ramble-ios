# Ramble Relay

The relay moves transcripts from Ramble to your agent. You talk to your watch, Ramble transcribes on the phone, and the relay holds the text until your agent picks it up. When the agent acknowledges it, the relay deletes it. Anything not picked up is deleted after 24 hours.

It's a Cloudflare Worker with a small D1 database. The code is here so you can check exactly what it does, or run your own.

## What it stores

This is the whole list:

| What | Fields | Deleted when |
|---|---|---|
| Inbox | random id, hash of the app's inbox secret, created time | — |
| Pairing code | hash of the code, inbox id, agent type, expiry | used, replaced, or 10 minutes pass |
| Connection | random id, inbox id, agent type, hash of the agent's token, created and last-pull times | you tap Disconnect |
| Queued transcript | recording id, recorded-at time, duration, text, expiry — one copy per connected agent | the agent acks it, you disconnect or tap Delete everything, or the retention window passes |

There are no accounts, emails, names, IP addresses, or audio. Audio never reaches the relay: transcription happens before upload, and on-device Apple Speech touches no server at all. Credentials are stored only as SHA-256 hashes. Logs record counts and ids, never transcript text.

We identify inboxes, not people.

## How it works

```
Watch ──► iPhone (transcribe) ──POST /inbox──► relay ──GET /inbox──► agent
                                                 ▲                      │
                                                 └──POST /inbox/ack─────┘ (deleted)
```

1. **Inbox.** When you turn the relay on, the app creates an inbox (`POST /inboxes`, App Attest required) and keeps the returned inbox secret in the Keychain.
2. **Pairing.** Settings → Connect agent shows a short code like `K7QX-MP4D`. You tell your agent "I downloaded Ramble, connect it" and paste the code. The agent exchanges it once for a long-lived token (`POST /pair/exchange`). This is the same shape as OAuth's device authorization grant: the code is single-use and dies in 10 minutes, so pasting it in chat is safe. The token goes in the agent's secret storage and never appears in chat.
3. **Upload.** Each transcript is uploaded once (`POST /inbox`) and copied into one queue per connected agent. If Muse acks first, ChatGPT's copy is untouched.
4. **Pull and ack.** The agent pulls on a schedule (`GET /inbox`), handles each transcript, then acks (`POST /inbox/ack`), which deletes it immediately.
5. **Expiry.** Unacknowledged transcripts disappear from pulls the moment they expire. A cron job every 15 minutes deletes them from disk.
6. **Disconnect.** Tapping Disconnect (`DELETE /connections/:id`) kills the token and deletes its queue. Delete everything now (`DELETE /inbox`) empties every queue.

## Authentication

| Direction | Credential | Header |
|---|---|---|
| App → relay | Inbox secret, plus an App Attest assertion when creating an inbox or uploading | `Authorization: Bearer rmbi_…`, `X-App-Attest-Key-Id`, `X-App-Attest` |
| Agent → relay | Connection token from the pairing exchange | `Authorization: Bearer rmba_…` |

App Attest uses the same scheme as the [transcription proxy](../proxy/README.md#app-attest-implementation-notes): the assertion signs a SHA-256 of the raw request body. The hosted relay shares the proxy's `ATTEST_KV`, so a device attested with the proxy doesn't attest again. A self-hosted relay serves `/attest/challenge` and `/attest` itself.

Disconnect, Delete everything, listing connections, and issuing pairing codes need only the inbox secret, so the kill switches keep working even if attestation is having a bad day.

Each credential works only on its own side: an agent token can't upload or manage connections, and the inbox secret can't pull.

## API

All bodies are JSON. Errors are `{"error": "..."}` with a 4xx/5xx status.

### App-facing

| Method | Path | Auth | Body → Response |
|---|---|---|---|
| `POST` | `/inboxes` | App Attest | — → `201 {"inbox_id", "inbox_secret"}` (secret is returned once) |
| `POST` | `/inbox` | App Attest + inbox secret | `{"recording_id", "created_at", "duration", "transcription"}` → `{"queued": <agents>, "expires_at"}` |
| `DELETE` | `/inbox[?connection_id=]` | inbox secret | — → `{"deleted": <n>}` |
| `POST` | `/pair/code` | inbox secret | `{"agent_type": "muse" \| "chatgpt" \| "grok" \| "claude" \| "other"}` → `201 {"code", "agent_type", "expires_at"}` |
| `GET` | `/connections` | inbox secret | — → `{"connections": [{"id", "agent_type", "created_at", "last_pull_at", "pending"}]}` |
| `DELETE` | `/connections/:id` | inbox secret | — → `{"status": "revoked"}` |

The upload body uses the same field names as the [webhook payload](../docs/webhook-api.md). Uploads are idempotent on `recording_id`, so the app's retry queue can resend safely. Issuing a new pairing code cancels the previous one. An inbox can have up to 10 connected agents.

### Agent-facing

**Exchange a pairing code** — no auth; the code is the credential.

```http
POST /pair/exchange
{"code": "K7QX-MP4D"}
```

```json
{"token": "rmba_…", "connection_id": "con_…", "agent_type": "muse", "retention_seconds": 86400}
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
{"deleted": 1}
```

Deletes those items now. Up to 500 ids per call. Ack only after the agent has durably handled the item; an unacked item is retried on the next pull until it expires.

### Other

| Method | Path | Description |
|---|---|---|
| `GET` | `/health` | `{"status": "ok"}` |
| `POST` | `/attest/challenge`, `/attest` | App Attest registration (same as the proxy) |

## For agents

The loop is small enough to describe to any agent that can make HTTP requests and keep a secret:

1. When the user says "I downloaded Ramble, connect it" and gives a code, `POST /pair/exchange` with it. Save `token` in secret storage. Don't repeat it back in chat.
2. On a schedule (every 15 minutes is a reasonable default), `GET /inbox` with the token.
3. For each item, do what the user asked in `transcription`. Use `recording_id` to skip anything already handled.
4. `POST /inbox/ack` with the ids you handled.
5. If a pull returns `401`, the user disconnected. Stop polling and tell them.

## Deploy Your Own

You need a Cloudflare account. The free tier is enough for personal use.

1. `cd relay && npm ci`
2. `cp wrangler.example.toml wrangler.toml` and set `account_id`.
3. Create the database and apply the schema:
   ```bash
   npx wrangler d1 create ramble-relay          # paste the id into wrangler.toml
   npx wrangler d1 migrations apply ramble-relay --remote
   ```
4. Create the App Attest store, or reuse your proxy's:
   ```bash
   npx wrangler kv namespace create ATTEST_KV  # paste the id into wrangler.toml
   ```
5. Optionally set `RETENTION_SECONDS` in `wrangler.toml` (default 86400, 24 hours).
6. `npx wrangler deploy`

App Attest only works from a real device running a copy of Ramble whose bundle ID matches. For simulator testing, `npx wrangler secret put DEV_BYPASS_TOKEN` and send it as `X-Dev-Bypass`; leave it unset in production.

`relay/wrangler.toml` is git-ignored so account-specific ids don't get committed.

### Local development

```bash
cp wrangler.example.toml wrangler.toml       # any placeholder ids work locally
echo 'DEV_BYPASS_TOKEN="dev"' > .dev.vars
npx wrangler d1 migrations apply ramble-relay --local
npm run dev
```

## Tests

```bash
npm test
```

The tests run every endpoint against the real schema, using Node's built-in SQLite in place of D1. App Attest is stubbed because it needs a real device. CI runs them on every PR touching `relay/` or the proxy's attest code.
