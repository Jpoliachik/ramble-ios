# Ramble Relay: agent API

How an agent receives Ramble transcripts. The person talks to their watch or iPhone, the device uploads the audio straight to Ramble's server, the server transcribes it, and the relay holds one copy of the transcript for each connected agent until that agent picks it up.

Ramble's server is a relay, not an archive. Your audio is sent to a transcription provider and deleted as soon as the transcript is ready. Transcripts are deleted when your agent picks them up, or after 30 days. Your full history lives only on your iPhone.

The full contract, including the phone and watch endpoints, is `specs/relay-api.md`. Person-facing agent docs are at https://ramble.watch/docs and https://ramble.watch/llms-full.txt; keep them in sync with this file. Running the Worker is in [README.md](README.md).

## Base URL

`https://api.ramble.watch`. Every path below is relative to it. `https://ramble-transcription-proxy.jpoliachik.workers.dev` serves the identical API, so agents paired against it keep working.

`GET /` on either host, with no credential, returns:

```json
{"service": "Ramble relay", "docs": "https://ramble.watch/docs", "llms": "https://ramble.watch/llms-full.txt"}
```

## Pairing

In Ramble on iPhone, Settings → Your agent → Connect your agent makes a pairing code and copies this message for the person to paste to their agent:

```
I downloaded Ramble, connect it. My pairing code is K7QX-MP4D-HN3R. Instructions: https://ramble.watch/docs
```

Codes are 12 characters from `23456789ABCDEFGHJKMNPQRSTVWXYZ`, shown as `XXXX-XXXX-XXXX`, single use, and expire 10 minutes after they are made. They match ignoring case, spaces and dashes.

| Method | Path | Body → Response |
|---|---|---|
| `POST` | `/pair/exchange` | `{"code", "request_id", "name"?}`, no credential → `201 {"token": "rmba_…"}` |

- `request_id` is a random string of 16–64 characters the agent picks. Retrying with the same code and `request_id` within the code's 10 minutes returns `200` and the same token. A different `request_id` on a used code gets `409` with `"reason": "code_used"` and no token.
- `name` is optional, 1–40 characters, and shows in the app. An invalid name is dropped without failing.
- An unknown or expired code gets `400` ("Invalid or expired pairing code. Ask the user for a new one in the Ramble app.").

## Agent endpoints

Send `Authorization: Bearer rmba_…`. `bearer <token>` and the bare token also work. Bodies are read as JSON whatever the `Content-Type`.

| Method | Path | Body → Response |
|---|---|---|
| `GET` | `/inbox` | → `{"items": [{"id", "recording_id", "created_at", "received_at", "duration", "transcription"}], "has_more"}` |
| `POST` | `/inbox/ack` | `{"ids": [1–500 integers]}` → `{"deleted": <n>}` |
| `GET` | `/agent` | → `{"name", "hook": null \| {"url", "header_names", "last_ping_at", "last_status"}}` |
| `PATCH` | `/agent` | `{"name"?, "hook"?: {"url", "headers"} \| null}` → same shape as `GET /agent` |

`GET /inbox` returns only this agent's copies, oldest first, up to 50. Unacked items come back on every pull; if `has_more` is true, ack and pull again.

| Field | Meaning |
|---|---|
| `id` | Integer item id, used to ack |
| `recording_id` | The note's UUID |
| `created_at` | When recording started, exactly as the recording device sent it, with its UTC offset (`2026-11-01T14:00:00-05:00`) |
| `received_at` | When the relay accepted the audio, ISO 8601 UTC with milliseconds (`2026-11-02T00:00:00.000Z`). Can be hours after `created_at` if the device was offline |
| `duration` | Length in seconds, measured by the relay |
| `transcription` | The full transcript |

Items carry no audio, device id or device name.

`POST /inbox/ack` deletes those of the agent's own copies. Ids that are gone or belong to another agent count as nothing. Any other body gets `400`.

### What an agent receives

- One copy of each note recorded after the agent paired, made when the transcript is ready. Notes recorded before pairing never reach it.
- Watch notes reach agents without the iPhone nearby.
- Notes with no speech detected produce no copy and no ping.
- A copy is deleted when the agent acks it, when the person disconnects the agent or taps Delete waiting notes, or 30 days after it was made.
- The token works until the person disconnects the agent. It reads and acks only that agent's copies; it can't pair agents, upload notes, or read the person's own copy. On an endpoint agents can't use it gets `403` with `"reason": "wrong_credential"` and keeps working.

## Wake-up hooks

Optional, for agents that can receive a webhook. The agent registers its own hook with `PATCH /agent`; nothing changes in the app.

- `url` must be `https://` with a public hostname (no IPs, `localhost`, `.local` or similar). Up to 8 headers and 4 KB; `Host`, `Content-Type`, `Content-Length`, `Connection`, `Transfer-Encoding`, `User-Agent` and `Cookie` can't be set. Anything else gets `400`.
- Header values are stored only encrypted and never shown again. If the relay can't encrypt, setting a hook gets `503`.
- Setting a hook sends one test ping at once (`"event": "ramble.test"`, text "Ramble test ping: your wake-up hook works. Nothing new to pick up, no action needed."), and `hook.last_status` reports its HTTP status (`0` = no response). `"hook": null` removes it.

When a copy is made for an agent with a hook, the relay POSTs:

```json
{"event": "ramble.notes_waiting", "text": "New Ramble notes are waiting. Pull them from …/inbox …", "pull_url": "https://api.ramble.watch/inbox"}
```

with the agent's headers, `Content-Type: application/json` and `User-Agent: Ramble-Relay/1 (+https://ramble.watch/docs)`.

- Pings never carry transcript text, note ids or counts. The agent pulls and acks as usual.
- One try, 5-second timeout, no redirects, and only after the hostname resolves to a public address. A failed ping never affects the note.
- After a ping, no other ping goes to that agent until it pulls or 10 minutes pass.
- Agents should keep a slow scheduled check (hourly or daily) as a fallback.

## Errors and limits

Errors are `{"error": "<sentence>"}`, plus `"reason"` where a client acts on it.

| Status | Meaning |
|---|---|
| `400` | Malformed request, or unknown or expired pairing code |
| `401` | Missing, unknown or revoked token: the person disconnected the agent. The only status that means stop |
| `403` | `wrong_credential` (endpoint agents can't use), or filtered before reaching the Worker (below) |
| `405` | Wrong method; the error names the right one and links https://ramble.watch/docs |
| `409` | `code_used`: the code was exchanged with another `request_id` |
| `429` | `rate_limited`, with `Retry-After` in seconds. Nothing changed; the token still works |
| `503` | `unavailable`: the relay couldn't check something and accepted nothing. Retry later |

Rate limits:

| What | Limit |
|---|---|
| `GET /inbox`, `POST /inbox/ack`, `GET /agent` | 60 per minute per agent token |
| `PATCH /agent` | 10 per hour per agent token |
| `POST /pair/exchange` | 100 failed attempts per hour per network address. Over 1,000 failed exchanges an hour from all addresses together, every exchange gets `503` until the hour ends |

Network addresses are used only by the limiter, never stored with notes or logged.

### Clients that get 403 before reaching the Worker

On `workers.dev`, Cloudflare's Browser Integrity Check runs before the Worker and can't be turned off. It rejects Python's built-in `urllib` default User-Agent (`Python-urllib/3.x`) with `403` and the body `error code: 1010`. curl, `requests`, `httpx`, Node `fetch`, and `urllib` with any other User-Agent reach the Worker. Agents should always send a User-Agent. On `api.ramble.watch` the check is switched off for the relay host (below).

## Agent guidance

The essentials the docs page teaches:

- **Separate checking from acting.** Empty checks drive the cost. A cheap watcher (script, hook, scheduled fetch) checks every few minutes and wakes the agent only when `items` isn't empty. If a platform can only schedule full agent runs, hourly or daily is fine.
- **Read relative times from `created_at`**, in its offset. If the moment has passed, the item is overdue.
- **Notes can arrive late and out of order** (watch offline or away from the iPhone, Low Power Mode, background uploads scheduled by watchOS, transcription retries during a provider outage). An empty inbox doesn't mean nothing was recorded.
- **Only 401 means stop.** On 429, wait `Retry-After`. 403, 5xx and timeouts are transient. Every call is safe to retry.
- **Send a User-Agent**, and a `name` at pairing so the person can tell agents apart.

To test: record "Test, remind me to water the plants" on the watch. Settings → Your agent shows one waiting. After the agent's next check it reads "nothing waiting".

## Operator: the api.ramble.watch domain

`ramble.watch` DNS is at Porkbun today, and a Worker custom domain needs the zone on Cloudflare. Until these steps are done, `api.ramble.watch` doesn't answer and agents must use the `workers.dev` host.

1. Cloudflare dashboard → Add a domain → `ramble.watch` (Free plan). Let it import the existing records, and make sure the Vercel ones (apex `A 76.76.21.21`, `www CNAME cname.vercel-dns.com`, or whatever Vercel shows) are **DNS only** (grey cloud), so Vercel keeps serving the site and its certificates.
2. Porkbun → ramble.watch → Nameservers → replace the four Porkbun ones with the two Cloudflare gives you. Wait for Cloudflare to say Active.
3. Workers & Pages → `ramble-transcription-proxy` → Settings → Domains & Routes → Add → Custom domain → `api.ramble.watch`.
4. Rules → Configuration Rules → Create: hostname equals `api.ramble.watch` → Browser Integrity Check **Off**. Leave Bot Fight Mode **off** (on the Free plan it can't be skipped per host). Security Level "Essentially off", or a WAF skip rule for that hostname, if anything else challenges API clients.
5. Keep the `workers.dev` route on, so shipped builds and already-paired agents keep working.
