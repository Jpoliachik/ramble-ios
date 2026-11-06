# Relay API

## Purpose
The HTTP contract of Ramble's relay: every endpoint, who may call it with which credential, request and response shapes, status codes, idempotency and rate limits. Its callers are the Ramble iPhone app, the Ramble watch app, and the user's agents. What the results mean to the person is defined in [transcription.md](transcription.md), [delivery.md](delivery.md) and [subscription.md](subscription.md).

## Endpoints at a glance

| Method and path | Caller | Credential |
|---|---|---|
| `POST /attest/challenge`, `POST /attest` | phone | none (App Attest registration) |
| `POST /inboxes` | phone | App Attest assertion |
| `GET /account` | phone, watch | inbox secret or watch token |
| `POST /entitlement` | phone | inbox secret |
| `GET /settings`, `PUT /settings` | phone | inbox secret |
| `POST /watch-token`, `DELETE /watch-token` | phone | inbox secret |
| `PUT /notes/:id` | phone, watch | inbox secret or watch token |
| `GET /notes/:id`, `POST /notes/lookup` | phone, watch | inbox secret or watch token |
| `GET /notes`, `POST /notes/ack` | phone | inbox secret |
| `POST /inbox/status`, `DELETE /inbox` | phone | inbox secret |
| `POST /pair/code`, `GET /connections`, `DELETE /connections/:id` | phone | inbox secret |
| `POST /pair/exchange` | agent | none (the pairing code) |
| `GET /inbox`, `POST /inbox/ack`, `GET /agent`, `PATCH /agent` | agent | agent key |
| `GET /`, `GET /health` | anyone | none |

## Basics

### Requirement: Base URL
The relay SHALL be served at `https://ramble-transcription-proxy.jpoliachik.workers.dev`, and every path in this spec SHALL be relative to it.

#### Scenario: Agent probes the base URL
- GIVEN an agent with no credential
- WHEN it sends `GET /`
- THEN it gets `200 {"service": "Ramble relay", "docs": "https://ramble.watch/docs", "llms": "https://ramble.watch/llms-full.txt"}`

### Requirement: Three credentials, each on its own side
Every call except pairing exchange, inbox creation and App Attest registration SHALL carry `Authorization: Bearer <credential>`, where the credential is an inbox secret (`rmbi_…`, the phone), a watch token (`rmbw_…`, the watch) or an agent key (`rmba_…`, an agent). Each is 32 random bytes, the relay SHALL store only its SHA-256 hash, and a credential used on an endpoint its caller may not use SHALL get `401`.

#### Scenario: Agent key on a phone endpoint
- GIVEN a valid agent key
- WHEN the agent calls `GET /connections` with it
- THEN the response is `401`

#### Scenario: Lenient header
- GIVEN a valid credential
- WHEN it is sent as `bearer <credential>` or as the bare credential with no scheme
- THEN the call is accepted

### Requirement: Errors are JSON with a stable reason
Every error SHALL be a JSON body `{"error": "<human-readable sentence>"}`, plus `"reason": "<code>"` wherever a client acts on the kind of error. Request bodies SHALL be parsed as JSON whatever their `Content-Type`, except note uploads, which are raw audio.

#### Scenario: Wrong method
- GIVEN an existing relay path
- WHEN it is called with a method it doesn't serve
- THEN the response is `405` and the error names the method to use and links https://ramble.watch/docs

#### Scenario: Revoked credential
- GIVEN an agent the user disconnected, or a watch token the phone revoked
- WHEN it calls any endpoint
- THEN the response is `401` with `"error": "Invalid or revoked credentials. Send \"Authorization: Bearer <token>\"."`

### Requirement: Timestamps
Times the relay produces SHALL be ISO 8601 UTC with milliseconds (`2026-11-01T19:00:04.120Z`). A note's recording time SHALL be returned exactly as the recording device sent it, offset included.

#### Scenario: Recording time passes through
- GIVEN a note uploaded with recording time `2026-11-01T14:00:00-05:00`
- WHEN the phone reads it or an agent pulls it
- THEN the recording time is `2026-11-01T14:00:00-05:00`, unchanged

## Phone setup

### Requirement: App Attest registration
`POST /attest/challenge` SHALL return `{"challenge"}`, valid once for 5 minutes for the device that asked. `POST /attest` with `{"keyId", "attestation", "challenge"}` SHALL return `200 {"status": "ok"}` only when the attestation chains to Apple's App Attest root (any failure to check the root rejects), its app identity hash equals SHA-256 of `SW6VLKWS7Q.dev.goodloop.Ramble`, and the key ID is new or already registered with the same public key; otherwise `403` (`409` with `"reason": "key_exists"` for a known key ID with a different public key). A registered key SHALL never be overwritten.

#### Scenario: Another developer's app
- GIVEN a valid attestation from an app with a different team or bundle ID
- WHEN it is sent to `POST /attest`
- THEN the response is `403` and nothing is stored

#### Scenario: Replaying a registration
- GIVEN a key ID already registered
- WHEN the same key ID is registered again with a different public key
- THEN the response is `409` and the stored key is unchanged

### Requirement: Creating an inbox
`POST /inboxes` SHALL require `X-App-Attest-Key-Id` and `X-App-Attest` (an assertion over the exact request body, which may be empty) and SHALL return `201 {"inbox_secret": "rmbi_…", "account_token": "<UUID>"}`. The account token identifies the inbox to the App Store. No production request SHALL skip attestation.

#### Scenario: Missing or bad assertion
- GIVEN a request without the headers, or with an assertion that fails or reuses a counter
- WHEN it is sent to `POST /inboxes`
- THEN the response is `403` with `"error": "App attestation required"` or `"App attestation failed"`, and no inbox is created

#### Scenario: Attestation only once
- GIVEN an inbox exists
- WHEN the phone later uploads, pairs or reads
- THEN only the inbox secret is checked

### Requirement: Account state
`GET /account` SHALL return `{"unlocked", "free_notes_total": 25, "free_notes_remaining", "fair_use_near"}` for the inbox, plus `"account_token"` when the caller is the phone. Meaning of each field: [subscription.md](subscription.md).

#### Scenario: Watch checks after a 402
- GIVEN the watch's last upload got `402`
- WHEN it calls `GET /account` and `unlocked` is now `true`
- THEN it can retry the upload

### Requirement: Submitting a purchase
`POST /entitlement` with `{"signed_transaction": "<JWS>"}` (the unlock purchase) or `{"app_transaction": "<JWS>"}` (proof of an earlier purchase) SHALL return `200` with the same body as `GET /account`, after checking the signature chains to Apple's root CA, the bundle ID and product, that the transaction is not revoked or refunded, and that it is not a Sandbox transaction on the production relay. Sending the same transaction again SHALL return `200` and change nothing. Grandfathering rules: [subscription.md](subscription.md).

#### Scenario: Forged or refunded transaction
- GIVEN a self-signed JWS, a refunded transaction, or a Sandbox transaction sent to production
- WHEN it is submitted
- THEN the response is `403` with `"reason": "invalid_transaction"` and the inbox stays locked

#### Scenario: Sixth inbox on one purchase
- GIVEN one purchase is already bound to 5 inboxes
- WHEN a sixth inbox submits it
- THEN the response is `403` with `"reason": "too_many_inboxes"`

### Requirement: Transcription settings
`GET /settings` and `PUT /settings` with `{"language": "<ISO-639-1>" | null, "remove_filler_words": <bool>, "vocabulary": "<text up to 900 characters>"}` SHALL read and replace the inbox's transcription options, which apply to every note accepted afterwards from the phone or the watch. `PUT` SHALL return the stored settings; a bad field gets `400`. What each option does: [transcription.md](transcription.md).

#### Scenario: Watch note uses the phone's language
- GIVEN the phone set `"language": "de"`
- WHEN the watch uploads a note
- THEN that note is transcribed with the German hint

### Requirement: Watch token
`POST /watch-token` SHALL return `201 {"watch_token": "rmbw_…"}` and revoke any earlier watch token for the inbox, so an inbox has at most one. `DELETE /watch-token` SHALL revoke it and return `200 {"revoked": <0 or 1>}`. Neither SHALL touch agent connections. A watch token SHALL be rejected with `401` once revoked, replaced, or its inbox no longer exists.

#### Scenario: Phone revokes the watch
- GIVEN a watch holding a token, and one connected agent
- WHEN the phone calls `DELETE /watch-token`
- THEN the watch's next call gets `401`
- AND the agent keeps pulling normally

## Notes

### Requirement: Note upload
`PUT /notes/:id` SHALL take the note's UUID in the path (any case; returned uppercase), the raw recording as the body with `Content-Type: audio/mp4` (or `audio/m4a`, `audio/x-m4a`, `audio/aac`) and `Content-Length`, and `X-Ramble-Recorded-At: <ISO 8601 with offset>`. The relay SHALL answer success only after the audio is fully stored, and SHALL create the note only then. Any duration the client sends SHALL be ignored.

#### Scenario: Accepted, transcript ready quickly
- GIVEN the inbox has free notes or is unlocked
- WHEN the phone or the watch uploads a short note
- THEN the response is `201` with the note (shape below) and `"status": "done"` with the transcript, if transcription finishes within 10 seconds of the audio being stored

#### Scenario: Accepted, transcript not ready yet
- GIVEN a long note
- WHEN the upload completes
- THEN the response is `201` with `"status": "transcribing"` and `"transcript": null`
- AND transcription continues on the relay even if the client disconnects

#### Scenario: Upload cut off
- GIVEN the connection drops before the whole body arrives
- WHEN the client retries
- THEN no note existed in between, and the retry is treated as a first upload

#### Scenario: Bad uploads
- GIVEN a body over 25 MB, no `Content-Length`, an empty body, a non-audio type, or a missing or invalid recording time
- WHEN it is uploaded
- THEN the response is `413`, `411`, `400`, `415` or `400` respectively, and nothing is stored or counted

### Requirement: Upload idempotency
The note UUID SHALL be the idempotency key: a repeated upload of an ID already accepted for the same inbox SHALL store nothing, count nothing, and return `200` with the note's current state; concurrent uploads of one ID SHALL produce one note counted once. An ID accepted for another inbox SHALL get `409` with `"reason": "id_in_use"`. The relay SHALL remember accepted IDs (with no audio or text) for 30 days.

#### Scenario: Watch retries after a lost response
- GIVEN a watch upload was accepted but the response never reached the watch
- WHEN the watch uploads the same note again
- THEN the response is `200` with the note's current status
- AND the free-note count is unchanged

### Requirement: Held uploads
An upload the inbox may not transcribe SHALL be refused before any audio is stored, so the device keeps its audio: `402` with `{"reason": "unlock_required", "free_notes_remaining": 0}` when out of free notes and not unlocked, and `429` with `{"reason": "fair_use"}` and `Retry-After` when over fair use. Meaning and copy: [subscription.md](subscription.md).

#### Scenario: Out of free notes
- GIVEN 25 notes already accepted and no purchase
- WHEN the watch uploads note 26
- THEN the response is `402` with `"reason": "unlock_required"`
- AND after `POST /entitlement` succeeds, the same upload returns `201`

### Requirement: The note shape
Note responses SHALL use this shape:
`{"id", "source": "watch" | "phone", "status": "transcribing" | "done" | "failed", "recorded_at", "received_at", "duration", "transcript", "transcript_cleared", "failure"}`.
`duration` is seconds as measured by the relay, `null` until done. `transcript` is the text once done, otherwise `null`. `transcript_cleared` is `true` once the device copy is gone. `failure` is a short reason code when failed, otherwise `null`; the codes and the empty-speech case are defined in [transcription.md](transcription.md).

#### Scenario: Done
- GIVEN a transcribed note the phone has not acked
- WHEN it is read
- THEN `status` is `"done"`, `transcript` holds the text and `transcript_cleared` is `false`

### Requirement: Reading notes by ID
`GET /notes/:id` SHALL return `200` with the note, and `POST /notes/lookup` with `{"ids": [up to 100 UUIDs]}` SHALL return `{"notes": [...], "missing": [ids]}`. The phone SHALL be able to read any note in its inbox; a watch token SHALL be able to read only notes uploaded from the watch on that inbox. Any other ID SHALL get `404` (or be listed in `missing`), whether or not it exists elsewhere.

#### Scenario: Watch reads its own note
- GIVEN a note the watch uploaded
- WHEN the watch reads it by ID with its token
- THEN it gets the status and transcript

#### Scenario: Watch asks for a phone note
- GIVEN a note recorded on the phone
- WHEN the watch reads its ID
- THEN the response is `404`

#### Scenario: Transcript already cleared
- GIVEN the phone acked a note, or it was transcribed more than 7 days ago
- WHEN it is read within 30 days of being accepted
- THEN `status` is `"done"`, `transcript` is `null` and `transcript_cleared` is `true`
- AND after 30 days the read is `404`

### Requirement: Phone lists its device copies
`GET /notes` (phone only) SHALL return `{"notes": [...], "next": <cursor> | null}`: every note in the inbox from either device whose device copy the phone has not acked, in any status, oldest accepted first, up to 50 per page; `GET /notes?after=<cursor>` returns the next page. This is how the phone learns of a watch note before the watch's own message about it arrives.

#### Scenario: Watch note the phone hasn't heard of
- GIVEN the watch uploaded a note while the phone was out of range of it
- WHEN the phone calls `GET /notes`
- THEN the note is listed with `"source": "watch"` and its current status
- AND the phone can create its row from that

#### Scenario: More than a page
- GIVEN 70 unacked notes
- WHEN the phone lists them
- THEN it gets 50 and a `next` cursor, and the rest with `?after=<cursor>`

### Requirement: Phone acks its device copies
`POST /notes/ack` (phone only) with `{"ids": [up to 500 UUIDs]}` SHALL delete the transcript of each listed note that is done or failed and return `{"acked": <n>, "not_final": [ids]}`, leaving notes still transcribing untouched and listed. Unknown or already acked IDs SHALL be ignored. Agent copies SHALL be unaffected. Device copies not acked SHALL be deleted 7 days after the transcript is ready.

#### Scenario: Ack before the transcript is ready
- GIVEN a note still transcribing
- WHEN the phone acks it
- THEN it appears in `not_final` and stays in `GET /notes`

## Agents and pairing

### Requirement: Pairing codes
`POST /pair/code` (phone) SHALL return `201 {"code", "expires_at"}`: 12 characters from `23456789ABCDEFGHJKMNPQRSTVWXYZ` shown as `XXXX-XXXX-XXXX`, single-use, valid 10 minutes. A new code SHALL cancel the inbox's previous one. At 10 connected agents it SHALL return `409` with `"reason": "too_many_agents"`.

#### Scenario: New code replaces the old
- GIVEN an unused code
- WHEN the phone asks for another
- THEN the first code no longer exchanges

### Requirement: Pairing exchange
`POST /pair/exchange` with `{"code", "name"?}` and no credential SHALL return `201 {"token": "rmba_…"}` and create one connection; `name` is optional, 1–40 characters, and an invalid name is dropped without failing the pairing. Codes SHALL be matched ignoring case, spaces and dashes. Retrying the same code SHALL return `200` with the same token until the agent's first pull or the code's expiry. An unknown, used or expired code SHALL get `400` with `"error": "Invalid or expired pairing code. Ask the user for a new one in the Ramble app."`. A new connection receives only notes recorded from then on ([delivery.md](delivery.md)).

#### Scenario: Lost response
- GIVEN an exchange succeeded but the agent never got the response
- WHEN it retries with the same code before its first pull
- THEN it gets `200` and the same token

### Requirement: Connections
`GET /connections` (phone) SHALL return `{"connections": [{"id", "name", "created_at", "last_pull_at", "pending", "hook"}]}`, where `pending` counts that agent's unacked copies and `hook` is `null` or `{"last_ping_at", "last_status"}`; hook URLs and headers SHALL never be returned to the phone. `DELETE /connections/:id` SHALL revoke that agent's key, delete its copies and return `{"status": "disconnected"}`, or `404` for an ID not in this inbox.

#### Scenario: Disconnect
- GIVEN a connected agent with 3 copies waiting
- WHEN the phone disconnects it
- THEN its next pull gets `401` and the 3 copies are gone

### Requirement: Agent pull
`GET /inbox` (agent) SHALL return `{"items": [{"id", "recording_id", "created_at", "received_at", "duration", "transcription"}], "has_more"}`: only that agent's copies, oldest first, up to 50, where `id` is an integer, `created_at` is the recording time as the device sent it, `received_at` is when the relay accepted the audio, and `duration` is relay-measured seconds. Unacked items SHALL come back on every pull.

#### Scenario: Nothing waiting
- GIVEN no copies for this agent
- WHEN it pulls
- THEN the response is `200 {"items": [], "has_more": false}`

### Requirement: Agent ack
`POST /inbox/ack` (agent) with `{"ids": [1–500 integers]}` SHALL delete those of the agent's own copies and return `{"deleted": <n>}`; IDs that are gone or not the agent's SHALL count as nothing. Anything else in the body SHALL get `400`. Unacked copies SHALL be deleted after 30 days.

#### Scenario: Acking someone else's item
- GIVEN item 41 belongs to another agent
- WHEN this agent acks 41
- THEN the response is `{"deleted": 0}` and item 41 remains

### Requirement: Delivery status for the phone
`POST /inbox/status` (phone) with `{"recording_ids": [1–100 note IDs]}` SHALL return `{"recordings": [{"recording_id", "waiting": <agents>}]}`, where `waiting` is how many agents still hold an unacked copy; `0` means every agent acked it, or it expired, or its agent was disconnected.

#### Scenario: Picked up
- GIVEN two agents each got a copy and one acked
- WHEN the phone asks
- THEN `waiting` is `1`

### Requirement: Agent name and wake-up hook
`GET /agent` SHALL return `{"name", "hook": null | {"url", "header_names", "last_ping_at", "last_status"}}`, never header values. `PATCH /agent` with `{"name"?, "hook"?: {"url", "headers"} | null}` SHALL update them and return the same shape; setting a hook sends one test ping (`"event": "ramble.test"`) at once and reports its HTTP status (`0` = no response), and `"hook": null` removes it. Hook URLs SHALL be `https://` with a public hostname; at most 8 headers, 4 KB in total, excluding `Host`, `Content-Type`, `Content-Length`, `Connection`, `Transfer-Encoding`, `User-Agent` and `Cookie`. Breaking these rules gets `400`.

#### Scenario: Ping when a transcript is ready
- GIVEN an agent with a hook
- WHEN a copy is queued for it after transcription
- THEN the relay POSTs `{"event": "ramble.notes_waiting", "text", "pull_url"}` with the agent's headers and `User-Agent: Ramble-Relay/1 (+https://ramble.watch/docs)`, once, with a 5-second timeout and no redirects
- AND sends no further ping until the agent pulls or 10 minutes pass
- AND the ping never carries transcript text

#### Scenario: Private hook URL
- GIVEN a hook URL of `https://192.168.1.5/run` or `https://box.local/run`
- WHEN the agent sets it
- THEN the response is `400`

## Deleting

### Requirement: Delete everything
`DELETE /inbox` (phone) SHALL delete every agent copy and every device copy in the inbox and return `{"deleted": <n>}`, leaving agent connections and the watch token in place. What happens to notes still transcribing: [delivery.md](delivery.md).

#### Scenario: Agents stay connected
- GIVEN two connected agents with copies waiting
- WHEN the phone deletes everything
- THEN both agents' next pulls return no items, and neither gets `401`

## Limits

### Requirement: Rate limits
The relay SHALL answer `429` with `{"reason": "rate_limited"}` and a `Retry-After` header in seconds when a caller exceeds these limits, and the call SHALL change nothing:

| What | Limit |
|---|---|
| `POST /attest/challenge` and `POST /attest` | 10 per hour per network address |
| `POST /inboxes` | 3 per day per App Attest key, 20 per hour per network address |
| `POST /pair/code` | 10 per hour per inbox |
| `POST /pair/exchange` | 10 failed attempts per hour per network address; then all attempts from it are refused until the hour ends |
| Connected agents | 10 per inbox (`409`, see Pairing codes) |
| `PUT /notes/:id` | 120 per hour and 500 per day per inbox, phone and watch together; repeats of an accepted ID don't count |
| Audio size | 25 MB per note (`413`) |
| Note reads (`GET /notes…`, `POST /notes/lookup`, `POST /notes/ack`, `POST /inbox/status`, `GET /account`) | 120 per minute per credential |
| Agent calls (`GET /inbox`, `POST /inbox/ack`, `GET /agent`) | 60 per minute per agent key |
| `PATCH /agent` | 10 per hour per agent key |
| `POST /entitlement`, `PUT /settings` | 20 per hour per inbox |
| `POST /watch-token` | 10 per day per inbox |

Network addresses SHALL be used only by the rate limiter for the length of its window and never stored with notes or logged.

#### Scenario: Guessing pairing codes
- GIVEN 10 failed exchanges from one address in the last hour
- WHEN an 11th arrives, even with a valid code
- THEN the response is `429` with `Retry-After`, and the code stays valid for its own use later

#### Scenario: Agent checking too often
- GIVEN an agent pulling every second
- WHEN it exceeds 60 calls in a minute
- THEN it gets `429` with `Retry-After`
- AND its key still works afterwards

### Requirement: Logs
Relay logs SHALL never contain request bodies, transcript text or audio, SHALL record device identifiers only as hashes, and SHALL truncate provider error bodies to 200 characters.

#### Scenario: Provider error
- GIVEN a provider returns a 5 KB error body
- WHEN the relay logs the failure
- THEN at most its first 200 characters are logged, with the hashed device ID

## Removed endpoints

### Requirement: Endpoints no longer served
The relay SHALL NOT transcribe audio sent to `POST /transcribe` and SHALL NOT accept text sent to `POST /inbox`; both SHALL answer `410` with `"error": "This version of Ramble is out of date. Update Ramble from the App Store."`.

#### Scenario: Old app build sends text
- GIVEN an app build from before cloud-only transcription
- WHEN it sends `POST /inbox` with a transcript
- THEN the response is `410` and nothing is queued for any agent
