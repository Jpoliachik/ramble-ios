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
| Pairing code | hash of the code, inbox id, expiry; once exchanged, the issued token and connection id | the agent's first pull, replaced, or 10 minutes pass |
| Connection | random id, inbox id, hash of the agent's token, created and last-pull times; optionally the name the agent gave itself and its wake-up hook (URL, headers, last ping time and status) | you tap Disconnect |
| Transcript | recording id, recorded-at time, received time, duration, text, expiry (one copy per connected agent) | the agent acks it, you disconnect, you tap Delete everything, or 30 days pass |

No accounts, emails, names, IP addresses, or audio. Credentials are stored only as SHA-256 hashes, with one exception: a freshly issued agent token sits next to its pairing code until the agent first pulls with it (at most 10 minutes), so a retried exchange gets the same token back. An agent's wake-up hook headers can't be hashed, because the relay has to send them back out. They're encrypted at rest with AES-GCM when the Worker has the `HOOK_ENCRYPTION_KEY` secret (`npx wrangler secret put HOOK_ENCRYPTION_KEY`, any long random string), and stored as plain JSON without it. They can only start that agent's own run, which then pulls with its separate token.

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
| `POST` | `/inbox/status` | `{"recording_ids": [...]}` → `{"recordings": [{"recording_id", "waiting": <agents>}]}`. Up to 100 ids. `waiting: 0` means every agent acked it (or it expired or its agent was disconnected). The app uses this to show "picked up". |
| `DELETE` | `/inbox` | → `{"deleted": <n>}` |
| `POST` | `/pair/code` | → `201 {"code", "expires_at"}`. A new code replaces the old one. |
| `GET` | `/connections` | → `{"connections": [{"id", "name", "created_at", "last_pull_at", "pending", "hook"}]}`. `name` is what the agent called itself, or `null`. `hook` is `null` or `{"last_ping_at", "last_status"}`; the hook URL and headers never come back to the app. |
| `DELETE` | `/connections/:id` | → `{"status": "disconnected"}` |

### Agent

| Method | Path | Body → Response |
|---|---|---|
| `POST` | `/pair/exchange` | `{"code": "K7QX-MP4D", "name": "Grok Bot"}`, no auth → `201 {"token"}`. `name` is optional (1–40 characters) and shows in the app. A retry with the same code returns `200` and the same token until the first pull. |
| `GET` | `/inbox` | → `{"items": [{"id", "recording_id", "created_at", "received_at", "duration", "transcription"}], "has_more"}`. Oldest first, up to 50. `created_at` is passed through as the app sent it (recording start, with the phone's UTC offset); `received_at` is the relay's clock, UTC, and `null` for items queued before migration 0003. |
| `POST` | `/inbox/ack` | `{"ids": [41, 42]}` → `{"deleted": <n>}`. Up to 500 ids. |
| `GET` | `/agent` | → `{"name", "hook": null \| {"url", "header_names", "last_ping_at", "last_status"}}`. Header values are never echoed. |
| `PATCH` | `/agent` | `{"name"?, "hook"?: {"url", "headers"} \| null}` → same as `GET /agent`. Setting a hook sends one test ping right away; `hook.last_status` is its HTTP status (`0` = no response). `"hook": null` removes it. |

### Wake-up hooks

Optional, for agents that can receive a webhook (for example a webhook-triggered routine). The agent registers its own URL and headers with `PATCH /agent`, so nothing in the app changes and the user never picks an agent type. When a transcript is queued for that agent, the relay POSTs:

```json
{"event": "ramble.notes_waiting", "text": "New Ramble notes are waiting. Pull them from …/inbox …", "pull_url": "https://…/inbox"}
```

with the agent's headers, `Content-Type: application/json`, and `User-Agent: Ramble-Relay/1`. The test ping has `"event": "ramble.test"`. The ping never carries transcript text: the agent pulls and acks as usual, so text only leaves through the token-protected pull.

- **One ping per batch.** After a ping, no more go out until the agent pulls, or 10 minutes pass (`HOOK_REPING_SECONDS`). A burst of recordings is one agent run, and a broken hook gets at most one ping per 10 minutes.
- **Best effort.** One attempt, 5-second timeout, no retries, redirects not followed. Agents should keep a slow scheduled check (hourly or daily) as a fallback.
- **Limits.** `https://` with a public hostname only (no IPs, `localhost`, `.local` or similar). Up to 8 headers, 4 KB total; `Host`, `Content-Type`, `Content-Length`, `User-Agent`, `Cookie` and a few others can't be set.

Codes are case-insensitive and ignore spaces and dashes. Unacked items come back on every pull, so if `has_more` is true, ack and pull again. A `401` on a pull means the user disconnected. A wrong method gets `405` with the right one in the error.

The Worker is lenient: it parses JSON whatever the `Content-Type`, and takes `Bearer <token>` in any case or the bare token. `GET /` returns a pointer to the docs.

### Clients that get 403 before reaching the Worker

On `workers.dev`, Cloudflare's Browser Integrity Check runs before the Worker and can't be turned off. It rejects Python's built-in `urllib` default User-Agent (`Python-urllib/3.x`) with `403` and the body `error code: 1010`. Verified Nov 4 2026: curl, `requests`, `httpx`, Node `fetch`, and `urllib` with any other User-Agent all reach the Worker. The docs tell agents to set a User-Agent. The full fix is serving the relay from a zone we control, where that check can be switched off for the relay host (see "Custom domain" below).

### Custom domain

`ramble.watch` DNS is at Porkbun today, and a Worker custom domain needs the zone on Cloudflare. Steps:

1. Cloudflare dashboard → Add a domain → `ramble.watch` (Free plan). Let it import the existing records, and make sure the Vercel ones (apex `A 76.76.21.21`, `www CNAME cname.vercel-dns.com`, or whatever Vercel shows) are **DNS only** (grey cloud), so Vercel keeps serving the site and its certificates.
2. Porkbun → ramble.watch → Nameservers → replace the four Porkbun ones with the two Cloudflare gives you. Wait for Cloudflare to say Active.
3. Workers & Pages → `ramble-transcription-proxy` → Settings → Domains & Routes → Add → Custom domain → `api.ramble.watch`.
4. Rules → Configuration Rules → Create: hostname equals `api.ramble.watch` → Browser Integrity Check **Off**. Then Security → Bots: leave Bot Fight Mode **off** (on the Free plan it can't be skipped per host). Security → Settings: Security Level "Essentially off" or a WAF skip rule for that hostname if anything else challenges API clients.
5. Keep the `workers.dev` route on, so shipped app builds and already-paired agents keep working. Then switch `Constants.Relay.hostedBaseURL` in the app, `RELAY_URL` in `website/src/lib/site.ts`, `llms*.txt`, and this file to `https://api.ramble.watch`.

## Agent instructions

The agent-facing instructions live on the website, at https://ramble.watch/docs (and `website/public/llms-full.txt` for agents that read plain text). The app's "Copy message" points agents there. Keep them in sync with this API. The essentials:

- **Separate checking from acting.** Empty checks drive the cost. A cheap watcher (script, hook, scheduled fetch) checks every few minutes and wakes the agent only when `items` isn't empty. If a platform can only schedule full agent runs, hourly or daily is fine.
- **`created_at` is when recording started**, with the phone's UTC offset; `received_at` is when the relay got it. Relative times are read from `created_at`, and if the moment has passed, the item is overdue.
- **Only 401 means stop.** 403, 5xx and timeouts are transient. Every call is safe to retry.
- **Set a User-Agent** (see below).
- **Optional: name and wake-up hook.** Send `name` at pairing so the user can tell agents apart. If the agent can receive webhooks, register one with `PATCH /agent` and pull when pinged.

To test: record "Test, remind me to water the plants" on the watch. Settings shows one waiting for the agent. After its next check the count drops to 0.

## Setup

1. `npx wrangler d1 create ramble-relay`
2. Uncomment the `[[d1_databases]]` block in `wrangler.toml` and paste the id.
3. `npx wrangler d1 migrations apply ramble-relay --remote`
4. `npx wrangler deploy`

Until the D1 binding exists, relay routes answer `503` and transcription works as before. A cron every 15 minutes deletes expired rows. New migrations (like `0002_pair_exchange_retry.sql`) must be applied with `npx wrangler d1 migrations apply ramble-relay --remote` **before** deploying the Worker that needs them.

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
