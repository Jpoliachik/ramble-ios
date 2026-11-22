# Relay API

## Purpose
The HTTP contract of Ramble's relay: every endpoint, who may call it with which credential, request and response shapes, status codes, idempotency and limits. Its callers are the Ramble iPhone app, the Ramble watch app and the user's agents. What results mean to the person is in [transcription.md](transcription.md), [delivery.md](delivery.md) and [purchase.md](purchase.md).

## Endpoints at a glance

| Method and path | Caller | Credential |
|---|---|---|
| `POST /attest/challenge`, `POST /attest` | phone | none (App Attest registration) |
| `POST /inboxes` | phone | App Attest assertion |
| `GET /account` | phone, watch | inbox secret or watch token |
| `POST /entitlement` | phone | inbox secret |
| `GET /settings`, `PUT /settings`, `POST /watch-token`, `DELETE /watch-token` | phone | inbox secret |
| `PUT /notes/:id`, `GET /notes/:id` | phone, watch | inbox secret or watch token |
| `GET /notes`, `POST /notes/ack`, `POST /inbox/status`, `DELETE /inbox`, `POST /pair/code`, `GET /connections`, `DELETE /connections/:id` | phone | inbox secret |
| `POST /pair/exchange` | agent | none (the pairing code) |
| `GET /inbox`, `POST /inbox/ack`, `GET /agent`, `PATCH /agent` | agent | agent key |
| `POST /mcp` | MCP connector ([connector.md](connector.md)) | agent key |
| `GET /.well-known/oauth-*`, `POST /register`, `GET`/`POST /authorize`, `POST /token` | MCP connector sign-in ([connector.md](connector.md)) | none (the pairing code, then OAuth) |
| `GET /`, `GET /health` | anyone | none |
| `POST /transcribe`, `POST /inbox`; `GET /analytics` | old builds | work until 2027-01-07 00:00 UTC, then `410`; `410` |

## Basics

### Requirement: Base URL
The relay SHALL be served at `https://api.ramble.watch`, and every path here is relative to it. `https://ramble-transcription-proxy.jpoliachik.workers.dev` SHALL serve the identical API, so agents paired against it keep working.

#### Scenario: Agent probes the base URL
- GIVEN an agent with no credential
- WHEN it sends `GET /` to either host
- THEN it gets `200 {"service": "Ramble relay", "docs": "https://ramble.watch/docs", "llms": "https://ramble.watch/llms-full.txt"}`

### Requirement: Three credentials
Calls other than pairing exchange, inbox creation and App Attest registration SHALL carry `Authorization: Bearer <credential>`: an inbox secret (`rmbi_…`, the phone), a watch token (`rmbw_…`, the watch) or an agent key (`rmba_…`, an agent). Each is 32 random bytes; the relay SHALL keep only a SHA-256 hash, never a readable copy. `bearer <credential>` and the bare credential are accepted. A missing, unknown or revoked credential SHALL get `401` ("Invalid or revoked credentials. Send \"Authorization: Bearer <token>\"."); a valid credential on an endpoint its caller may not use SHALL get `403` with `"reason": "wrong_credential"` and keep working.

#### Scenario: Lenient header
- GIVEN a valid agent key
- WHEN it is sent with no `Bearer` prefix
- THEN the call is accepted

#### Scenario: Agent calls a phone endpoint
- GIVEN a valid agent key
- WHEN the agent calls `GET /connections`
- THEN the response is `403` with `"reason": "wrong_credential"`, and its next `GET /inbox` succeeds

### Requirement: Errors, and failing closed
Every error SHALL be `{"error": "<sentence>"}`, plus `"reason": "<code>"` wherever a client acts on the kind of error, except on the connector's sign-in and MCP endpoints, which use OAuth and JSON-RPC errors ([connector.md](connector.md)). Bodies SHALL be read as JSON whatever their `Content-Type`, except note uploads, which are raw audio, and `POST /authorize` and `POST /token`, which also take form-encoded bodies. A wrong method on an existing path SHALL get `405` naming the right method and linking https://ramble.watch/docs. When the relay cannot check a credential, a count, an entitlement or a limit, it SHALL answer `503` with `"reason": "unavailable"` and accept, store and count nothing; production honors no developer bypass.

#### Scenario: Wrong method
- GIVEN the path `/inbox/ack`
- WHEN it is called with `GET`
- THEN the response is `405` and the error says to use `POST`

#### Scenario: Database unreachable during an upload
- GIVEN the free-note count can't be read
- WHEN the watch uploads a note
- THEN the response is `503`, nothing is stored or counted, and the watch keeps its audio

## Phone setup and purchase

### Requirement: App Attest registration
`POST /attest/challenge` SHALL return `{"challenge"}`, usable once within 5 minutes. `POST /attest` with `{"keyId", "attestation", "challenge"}` SHALL return `200 {"status": "ok"}` only when the attestation chains to Apple's App Attest root, comes from the production App Attest environment, and its app identity hash equals SHA-256 of `SW6VLKWS7Q.dev.goodloop.Ramble`. Any failure, including being unable to check the root, SHALL get `403`. A known key ID with the same public key SHALL get `200` and change nothing; with a different one, `409` with `"reason": "key_exists"`.

#### Scenario: Another developer's app, or a development attestation
- GIVEN a valid attestation from an app with a different team or bundle ID, or from the App Attest development environment
- WHEN it is registered with the production relay
- THEN the response is `403` and nothing is stored

#### Scenario: Overwrite attempt
- GIVEN a registered key ID
- WHEN it is registered with another public key
- THEN the response is `409` and the stored key is unchanged

### Requirement: Creating an inbox
`POST /inboxes` SHALL require `X-App-Attest-Key-Id` and `X-App-Attest` (an assertion over the exact body, which may be empty) and return `201 {"inbox_secret": "rmbi_…"}`. A missing assertion gets `403` "App attestation required"; a failing one, or one reusing a counter, `403` "App attestation failed". After that only the inbox secret is checked. A local development relay, and never production, SHALL also accept its configured developer key in `X-Dev-Bypass` in place of the assertion, on this endpoint only. A phone that still holds its inbox secret after a reinstall SHALL keep using that inbox. Every new inbox SHALL start locked with 25 free notes, whatever the body carries; a purchase is bound afterwards with `POST /entitlement`. There SHALL be no daily cap on inboxes overall, only the per-key and per-address limits ("Rate limits").

#### Scenario: A body never unlocks
- GIVEN a valid assertion over a body holding a verified unlock purchase
- WHEN a phone creates an inbox with it
- THEN the response is `201` and `GET /account` reads `"unlocked": false, "free_notes_remaining": 25`

### Requirement: Account state
`GET /account` SHALL return `{"unlocked", "free_notes_total": 25, "free_notes_remaining"}`, the same for the phone and the watch. It SHALL NOT report usage or a suspension. Meaning: [purchase.md](purchase.md).

#### Scenario: Unlocked inbox
- GIVEN an unlocked inbox whose purchase transcribed 141 hours this month
- WHEN the phone reads `GET /account`
- THEN the body is `{"unlocked": true, "free_notes_total": 25, "free_notes_remaining": 25}`, with no usage in it

### Requirement: Submitting a purchase
`POST /entitlement` with `{"signed_transaction": "<JWS>"}` or, for early buyers, `{"app_transaction": "<JWS>"}` SHALL return `200` with the `GET /account` body once the record is verified: signature chained to Apple's root CA, bundle ID `dev.goodloop.Ramble`, not revoked or refunded, not from Xcode testing. A Sandbox unlock purchase (TestFlight, App Review) unlocks like a Production one, and a Sandbox app transaction is never early-buyer proof ([purchase.md](purchase.md)). A transaction SHALL be for the unlock product; `dev.goodloop.ramble.premium.monthly2` is accepted only as early-buyer proof ([purchase.md](purchase.md)). Re-sending a bound record SHALL return `200` and change nothing.

#### Scenario: Forged or refunded record
- GIVEN a self-signed JWS, a refunded transaction, or an Xcode test record sent to production
- WHEN it is submitted
- THEN the response is `403` with `"reason": "invalid_transaction"` and the inbox stays locked

### Requirement: Purchases are bound to inboxes
Any inbox MAY submit a purchase, whichever inbox it was bought from. A purchase SHALL unlock at most 10 inboxes ever (or the higher cap the operator set on it), keyed on the original transaction ID (or the app transaction ID for early buyers); a binding is never released. Family-shared purchases SHALL NOT unlock.

#### Scenario: Eleventh inbox
- GIVEN one purchase bound to 10 inboxes, whether or not they still upload
- WHEN an eleventh inbox submits it
- THEN the response is `403` with `"reason": "too_many_inboxes"`

### Requirement: Revoked purchases
The relay SHALL NOT receive App Store Server Notifications. A purchase the operator marks revoked by hand ([proxy/README.md](../proxy/README.md) "Operations") SHALL return every inbox bound to it to the free state, with its used free-note count unchanged, and SHALL be refused as `invalid_transaction` when submitted again.

#### Scenario: Refund revoked by hand
- GIVEN a purchase bound to 2 inboxes that used all 25 free notes before unlocking
- WHEN the operator marks it revoked
- THEN both inboxes read `"unlocked": false, "free_notes_remaining": 0`, and their next uploads get `402` with `"reason": "free_notes_used"`

### Requirement: Transcription settings
`GET /settings` SHALL return `{"language": "<ISO 639-1 code, or ISO 639-3 where none exists>" | null, "remove_filler_words": <bool>, "vocabulary": "<up to 900 characters>"}`; `PUT /settings` with that body SHALL replace it and return what is stored, and a bad field gets `400` and changes nothing. When options apply and what they do: [transcription.md](transcription.md).

#### Scenario: Too much vocabulary
- GIVEN the phone stored `"language": "haw"`
- WHEN it sends `PUT /settings` with 901 characters of vocabulary
- THEN the response is `400`, and `GET /settings` still returns `"language": "haw"`

### Requirement: Watch token
`POST /watch-token` with `{"replaces": "<the watch's previous token>"?}` SHALL return `201 {"watch_token": "rmbw_…"}` and revoke the token named in `replaces` (even one of an earlier inbox) and any other watch token of this inbox, so an inbox has one. `DELETE /watch-token` SHALL revoke it and return `200 {"revoked": <0 or 1>}`. Neither touches agent connections. A replaced or revoked token SHALL get `401` on every call, including reads of notes it uploaded. When the phone calls these: [phone.md](phone.md).

#### Scenario: Revoked
- GIVEN a watch token and one connected agent
- WHEN the phone calls `DELETE /watch-token`
- THEN every call with that token gets `401`, and the agent keeps pulling

#### Scenario: Token replaced in the same inbox
- GIVEN the inbox accepted a watch note that is still transcribing
- WHEN the phone mints a new watch token
- THEN the old token gets `401`, and the new token reads that note

#### Scenario: Phone reinstalled with a fresh inbox
- GIVEN the old inbox accepted a watch note that is still transcribing
- WHEN the reinstalled phone mints a token with the old one as `replaces`
- THEN the old token gets `401`, and the new token reading that note gets `404`

## Notes

### Requirement: Note upload request
`PUT /notes/:id` SHALL take the note's UUID in the path (any case, returned uppercase), the raw recording as the body with `Content-Type` `audio/mp4`, `audio/m4a`, `audio/x-m4a` or `audio/aac`, a `Content-Length`, and `X-Ramble-Recorded-At: <ISO 8601 with offset>`. Note IDs SHALL be scoped to the inbox, and `source` SHALL be `"watch"` or `"phone"` by the uploading credential. Any client-sent duration is ignored. `X-Ramble-Client` is described in [usage.md](usage.md).

#### Scenario: Same UUID in two inboxes
- GIVEN inbox A holds note `6F1C…`
- WHEN inbox B uploads a note with the same ID
- THEN B's note is accepted as its own, and neither inbox can see the other's

### Requirement: Upload acceptance
The relay SHALL answer success only after the audio is fully stored, and create the note only then. A first upload SHALL get `201` with the note: `"status": "done"` if the transcript is ready within 8 seconds of the audio being stored, else `"transcribing"`. A repeat gets `200` (below). Clients SHALL allow at least 30 seconds for the response. Transcription continues if the client disconnects.

#### Scenario: Short note
- GIVEN the inbox may transcribe
- WHEN the watch uploads a 10-second note
- THEN the response is `201` with `"status": "done"` and the transcript

### Requirement: Upload refusals
The relay SHALL refuse these uploads, storing and counting nothing. Refusals marked final cannot succeed for that audio; devices stop retrying, keep the audio and raise no stuck alert ([watch.md](watch.md), [phone.md](phone.md)).

| Condition | Status | `reason` | Final |
|---|---|---|---|
| Container says longer than 61 minutes; body over 20 MB | `413` | `too_long`; `too_large` | yes |
| Not one of the audio types above | `415` | `unsupported_type` | yes |
| Empty body, body bytes ≠ `Content-Length`, missing or invalid recorded time | `400` | `bad_upload` | yes |
| The inbox, or the purchase it is bound to, is suspended by the operator ([purchase.md](purchase.md)) | `403` | `suspended` | yes |
| No `Content-Length` (`411`), or body not finished within 30 minutes (`408`) | `411` / `408` | `length_required` / `upload_timeout` | no |

The recorded time is stored and returned as sent and is never checked against the relay's clock.

#### Scenario: Watch clock far ahead
- GIVEN a watch whose clock is an hour fast
- WHEN it uploads a note
- THEN the note is accepted like any other, with `recorded_at` as the watch sent it

#### Scenario: Suspended user
- GIVEN the operator suspended an inbox
- WHEN its watch or phone uploads a new note
- THEN the response is `403` with `"reason": "suspended"`, nothing is stored or counted, and a repeat of a note accepted before still gets `200`

### Requirement: Upload idempotency and retries
The note UUID SHALL be the idempotency key within an inbox. A repeated upload of an accepted ID without a valid retry (below) SHALL be answered `200` with the note's current state before the body is read, storing and counting nothing. Concurrent uploads of one ID SHALL produce one note, counted once. An upload of an ID this inbox already holds but the uploading credential may not read (a watch reusing a phone note's ID) SHALL get `409` with `"reason": "id_in_use"`, changing nothing.

#### Scenario: Lost response
- GIVEN a watch upload was accepted but the response never arrived
- WHEN the watch uploads the same note again
- THEN the response is `200` with the current status, and the free-note count is unchanged

`PUT /notes/:id` from the phone with `X-Ramble-Retry: 1`, on a note whose `status` is `"failed"` and that has not been retried, SHALL be checked like a first upload (refusals, including `suspended`) but never held for free notes and never counted, then SHALL replace the audio, start a fresh transcription, list the note again in `GET /notes`, and answer `201` like a first upload; `id`, `source` and `recorded_at` stay. On a note not failed, or from a watch token, the header is ignored. A note SHALL be retried at most once: a second retry gets `409` with `"reason": "retry_limit"`, changing nothing. Concurrent retries of one note SHALL start one.

#### Scenario: Second retry
- GIVEN a note that failed again after its retry
- WHEN the phone sends `PUT /notes/:id` with `X-Ramble-Retry: 1`
- THEN the response is `409` with `"reason": "retry_limit"`, and nothing is transcribed or counted

#### Scenario: Retry with no free notes left
- GIVEN a failed note in an inbox that has used all 25 free notes and is not unlocked
- WHEN the phone retries it
- THEN the response is `201`, and the free-note count is unchanged

### Requirement: Held uploads
An upload the inbox may not transcribe SHALL get `402` with `{"reason": "free_notes_used", "free_notes_remaining": 0}` when out of free notes and not unlocked, keeping and counting nothing. An unlocked inbox SHALL never be held for how much audio it sends. Meaning and copy: [purchase.md](purchase.md).

#### Scenario: Out of free notes
- GIVEN 25 notes accepted and no purchase
- WHEN note 26 is uploaded
- THEN the response is `402` with `"reason": "free_notes_used"`, and after `POST /entitlement` succeeds the same upload gets `201`

### Requirement: The note shape
Note responses SHALL be `{"id", "source", "status", "result", "recorded_at", "received_at", "duration", "transcript", "transcript_cleared"}`. Times the relay produces are ISO 8601 UTC with milliseconds. Meaning: [transcription.md](transcription.md).

| Field | Values |
|---|---|
| `status` | `"transcribing"`, `"done"` or `"failed"` |
| `result` | done: `"transcript"` or `"no_speech"`; failed: `"audio_rejected"` (Groq rejected the audio itself) or `"retries_exhausted"` (it kept failing until the retry window ended); else `null` |
| `recorded_at` | exactly as the device sent it, offset included |
| `duration` | seconds measured by the relay; `null` until done |
| `transcript` | the text for `"transcript"`, `""` for `"no_speech"`, else `null` |
| `transcript_cleared` | `true` once the copy for the person's devices is gone |

#### Scenario: Silent note
- GIVEN a note in which no speech was detected
- WHEN it is read
- THEN `status` is `"done"`, `result` is `"no_speech"` and `transcript` is `""`

### Requirement: Reading a note by ID
`GET /notes/:id` SHALL return `200` with the note. The phone reads any note in its inbox; the inbox's watch token reads only notes uploaded with a watch token of that inbox, including ones uploaded with a token since replaced. Any other ID SHALL get `404`. Once the copy for the person's devices is gone, the note SHALL read with `"transcript": null` and `"transcript_cleared": true` for 30 more days, then `404`.

#### Scenario: Watch asks for a phone note
- GIVEN a note recorded on the phone
- WHEN the watch reads its ID
- THEN the response is `404`

### Requirement: Copy kept for the person's devices
A note's transcript SHALL stay readable by the person's devices until the phone has acked it and, for a watch note, the watch has received it as done or failed, in an upload response or a `GET /notes/:id`; and at most 30 days after it is ready. Meaning: [delivery.md](delivery.md).

#### Scenario: Phone acks before the watch looks
- GIVEN the phone acked a watch note whose upload response said `"transcribing"`
- WHEN the watch first reads it
- THEN it gets the transcript, and later reads show `"transcript_cleared": true`

### Requirement: Phone lists notes
`GET /notes` (phone) SHALL return `{"notes": [...], "next": <cursor> | null}`: every note in the inbox, from either device and in any status, that the phone has not acked, oldest accepted first, 50 per page; `GET /notes?after=<cursor>` returns the next page.

#### Scenario: Watch note the phone hasn't heard of
- GIVEN the watch uploaded a note while out of reach of the phone
- WHEN the phone calls `GET /notes`
- THEN the note is listed with `"source": "watch"` and its status

### Requirement: Phone acks notes
`POST /notes/ack` (phone) with `{"ids": [up to 500 UUIDs]}` SHALL mark each done or failed note as acked by the phone and return `{"acked": <n>, "not_final": [ids]}`. Notes still transcribing stay unacked and are listed in `not_final`. Unknown or already acked IDs are ignored; agent copies are unaffected.

#### Scenario: Ack too early
- GIVEN a note still transcribing
- WHEN the phone acks it
- THEN it is in `not_final` and stays in `GET /notes`

## Agents and pairing

### Requirement: Pairing codes
`POST /pair/code` (phone) SHALL return `201 {"code", "expires_at"}`: 12 characters from `23456789ABCDEFGHJKMNPQRSTVWXYZ`, shown as `XXXX-XXXX-XXXX`, single-use, expiring 10 minutes after it is made. Making another code SHALL replace the previous one. With 10 agents connected it gets `409` with `"reason": "too_many_agents"`.

#### Scenario: Second code
- GIVEN an unused code
- WHEN the phone asks for another
- THEN the first code fails to exchange

### Requirement: Pairing exchange
`POST /pair/exchange` with `{"code", "name"?}` and no credential SHALL return `201 {"token": "rmba_…"}` and create one connection. `name` is optional, 1–40 characters, and an invalid name is dropped without failing; any other field, such as a `request_id` older instructions send, is ignored. Codes match ignoring case, spaces and dashes. A code SHALL make one connection and return its key once. An unknown or expired code SHALL get `400` ("Invalid or expired pairing code. Ask the user for a new one in the Ramble app."); a code already exchanged, while it hasn't expired and its connection still exists, or already entered on a connector's sign-in page ([connector.md](connector.md)), `409` with `"reason": "code_used"` and no key. A code made before the inbox reached 10 agents SHALL get `409` with `"reason": "too_many_agents"` and make nothing. Which notes the connection receives: [delivery.md](delivery.md).

#### Scenario: Response lost
- GIVEN an exchange succeeded but the response never reached the agent
- WHEN the agent sends the same code again
- THEN the response is `409` with `"reason": "code_used"` and no key, the unused connection shows as "Hasn't checked in yet" ([agents-screen.md](agents-screen.md)), and the user makes a new code

#### Scenario: Someone else replays the code
- GIVEN a code already exchanged
- WHEN anyone sends it again
- THEN the response is `409`, and no key is returned

### Requirement: Connections
`GET /connections` (phone) SHALL return `{"connections": [{"id", "name", "label", "created_at", "last_pull_at", "pending", "hook"}]}`: `name` is the agent's own name, `label` the person's name for it, each `null` when unset; `pending` counts that agent's unacked copies; `hook` is `null` or `{"last_ping_at", "last_status"}`, never the URL or headers. `PATCH /connections/:id` (phone) with `{"label": "…" | null}` SHALL set or clear the label (1–40 characters after trimming, else `400`) and return that connection in the same shape, or `404` for an ID not in this inbox. Agents can't read or change a label. `DELETE /connections/:id` SHALL revoke that agent's key, delete its copies and return `{"status": "disconnected"}`, or `404` for an ID not in this inbox.

#### Scenario: Disconnect
- GIVEN a connected agent with 3 copies waiting
- WHEN the phone disconnects it
- THEN its next pull gets `401` and the 3 copies are gone

### Requirement: Agent pull and ack
`GET /inbox` (agent) SHALL return `{"items": [{"id", "recording_id", "created_at", "received_at", "duration", "transcription"}], "has_more"}`: that agent's copies only, oldest first, up to 50. `id` is an integer, `created_at` the recorded time as sent, `received_at` when the relay accepted the audio, `duration` relay-measured seconds. Unacked items SHALL come back on every pull. `POST /inbox/ack` with `{"ids": [1–500 integers]}` SHALL delete those of the agent's own copies and return `{"deleted": <n>}`; IDs gone or not the agent's count as nothing; any other body gets `400`. Unacked copies SHALL be deleted 30 days after they are made.

#### Scenario: Nothing waiting
- GIVEN no copies for this agent
- WHEN it pulls
- THEN the response is `200 {"items": [], "has_more": false}`

#### Scenario: Someone else's item
- GIVEN item 41 belongs to another agent
- WHEN this agent acks 41
- THEN the response is `{"deleted": 0}` and item 41 remains

### Requirement: Delivery status
`POST /inbox/status` (phone) with `{"recording_ids": [1–100 note IDs]}` SHALL return `{"recordings": [{"recording_id", "copies", "waiting", "picked_up", "removed", "first_picked_up_at", "agents"}], "missing": [ids]}`: agent copies made, still waiting, acked, and removed unread (expired, deleted, or agent disconnected), the first ack time or `null`, and `agents`, one `{"connection_id", "name", "state", "picked_up_at"}` per copy in the order copies were made, with `state` `"waiting"`, `"picked_up"` or `"removed"`, and `name` the connection's label if set, else the agent's own name, or `null` when it has neither or has since been disconnected. IDs this inbox doesn't know are listed only in `missing`. States: [delivery.md](delivery.md).

#### Scenario: Removed unread
- GIVEN a note copied to one agent, which was disconnected before pulling
- WHEN the phone asks
- THEN it gets `"copies": 1, "waiting": 0, "picked_up": 0, "removed": 1, "first_picked_up_at": null`, and one entry in `agents` with `"state": "removed"` and `"name": null`

### Requirement: Agent name and wake-up hook
`GET /agent` SHALL return `{"name", "hook": null | {"url", "header_names", "last_ping_at", "last_status"}}`, never header values; `PATCH /agent` with `{"name"?, "hook"?}` updates them and returns the same shape. `name` is 1–40 characters or `null`. A hook `{"url", "headers"}` SHALL be `https://` with a public hostname, at most 8 headers and 4 KB, none of `Host`, `Content-Type`, `Content-Length`, `Connection`, `Transfer-Encoding`, `User-Agent`, `Cookie`; otherwise `400`. Setting one sends a test ping (`"event": "ramble.test"`) and reports its status (`0` = no response); `null` removes it. Headers are stored only encrypted; without encryption, setting a hook gets `503`.

#### Scenario: Private hook URL
- GIVEN a hook URL of `https://192.168.1.5/run` or `https://box.local/run`
- WHEN the agent sets it
- THEN the response is `400`

### Requirement: Wake-up pings
When a copy is made for an agent with a hook, the relay SHALL POST `{"event": "ramble.notes_waiting", "text", "pull_url"}` with the agent's headers and `User-Agent: Ramble-Relay/1 (+https://ramble.watch/docs)`, once, with a 5-second timeout and no redirects. No further ping goes out until the agent pulls or 10 minutes pass. Pings SHALL never carry transcript text. A ping that gets no response records `last_status` `0`.

#### Scenario: Burst of notes
- GIVEN an agent with a hook that hasn't pulled since its last ping 3 minutes ago
- WHEN another copy is made for it
- THEN no ping is sent, and the next one can go out once the agent pulls or the 10 minutes pass

### Requirement: Delete waiting notes
`DELETE /inbox` (phone) SHALL delete every agent copy still waiting in the inbox and return `{"deleted": <n>}`. It SHALL NOT delete the copy for the person's devices, notes still transcribing, agent connections, the watch token, the free count or the unlock. Meaning: [delivery.md](delivery.md).

#### Scenario: Unpulled watch note survives
- GIVEN a watch note the phone hasn't pulled, and its agent copy waiting
- WHEN the phone calls `DELETE /inbox`
- THEN the agent copy is gone, and `GET /notes` still lists the note with its transcript

## Limits

### Requirement: Rate limits
Over these limits the relay SHALL answer `429` with `{"reason": "rate_limited"}` and `Retry-After` in seconds, and change nothing. No other endpoint is rate-limited: agents, the MCP connector, uploads, reads and pairing have no per-caller limit. Network addresses are used only by the limiter for its window, never stored with notes or logged.

| What | Limit |
|---|---|
| `POST /attest/challenge`; `POST /attest` | 20 per hour; 5 key registrations per day; per network address |
| `POST /inboxes` | 3 per day per App Attest key, 20 per hour per network address |
| `POST /register` (connector clients) | 600 per hour per network address |

#### Scenario: Agent checking often
- GIVEN an agent pulling every second
- WHEN it passes 100 calls in a minute
- THEN every pull succeeds

#### Scenario: Failed pairing exchanges
- GIVEN 150 failed exchanges this hour from one address
- WHEN an agent sends a valid code
- THEN it gets `201` and a key

### Requirement: Logs
Relay logs SHALL contain no request bodies, transcript text, audio, credentials or network addresses, SHALL record inbox IDs and App Attest key IDs only as hashes, and SHALL keep at most 200 characters of a provider error body.

#### Scenario: Provider error
- GIVEN a provider returns a 5 KB error body
- WHEN the relay logs the failure
- THEN at most its first 200 characters are logged, with the hashed inbox ID

## Old app versions

### Requirement: Old builds work until 2027-01-07, then are told to update
Old builds' paths retire at a fixed date, 2027-01-07 00:00 UTC, fixed in the relay's code. Until then, `POST /transcribe` (cloud transcription for early subscribers) and text `POST /inbox` (old builds delivering transcripts to agents) SHALL keep working for old builds, under these checks:

- Text `POST /inbox` needs only the old build's inbox secret, as today, and no purchase record, so $4.99 buyers' old builds keep delivering.
- `POST /transcribe` needs the App Attest checks above and a subscription record that passes the same checks as `POST /entitlement` and has not expired. It SHALL apply the upload size limits above, add transcribed audio to the monthly usage tally of its original transaction (monitoring only, never a cap; [purchase.md](purchase.md)), refuse with `403` and `"reason": "suspended"` when the operator suspended that transaction, and always transcribe with Groq ([transcription.md](transcription.md)), ignoring any model the client asks for. `GET /analytics`, and from 2027-01-07 00:00 UTC on those two paths, SHALL answer `410` with `"error": "This version of Ramble is out of date. Update Ramble from the App Store."`, and SHALL transcribe, queue or reveal nothing.

#### Scenario: Old subscriber before and after the date
- GIVEN an old build with an active subscription and a valid App Attest assertion
- WHEN it sends `POST /transcribe` with audio before 2027-01-07
- THEN it gets the transcript
- AND from 2027-01-07 00:00 UTC on, that request or a text `POST /inbox` gets `410`, and nothing is transcribed or queued for any agent

#### Scenario: Old $4.99 build delivers text
- GIVEN an old build of a $4.99 buyer with no subscription, transcribing on device
- WHEN it sends a text `POST /inbox` before 2027-01-07
- THEN the transcript is queued for its agents as before

#### Scenario: Expired subscription on the old path
- GIVEN an old build whose subscription record expired last month
- WHEN it sends `POST /transcribe` before 2027-01-07
- THEN the response is `403`, and nothing is transcribed
