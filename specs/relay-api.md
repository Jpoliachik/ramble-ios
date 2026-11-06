# Relay API

## Purpose
The HTTP contract of Ramble's relay: every endpoint, who may call it with which credential, request and response shapes, status codes, idempotency and limits. Its callers are the Ramble iPhone app, the Ramble watch app, the user's agents, and Apple. What results mean to the person is in [transcription.md](transcription.md), [delivery.md](delivery.md) and [subscription.md](subscription.md).

## Endpoints at a glance

| Method and path | Caller | Credential |
|---|---|---|
| `POST /attest/challenge`, `POST /attest` | phone | none (App Attest registration) |
| `POST /inboxes` | phone | App Attest assertion |
| `GET /account` | phone, watch | inbox secret or watch token |
| `POST /entitlement` | phone | inbox secret |
| `POST /appstore/notifications` | Apple | Apple-signed body |
| `GET /settings`, `PUT /settings` | phone | inbox secret |
| `POST /watch-token`, `DELETE /watch-token` | phone | inbox secret |
| `PUT /notes/:id`, `GET /notes/:id` | phone, watch | inbox secret or watch token |
| `GET /notes`, `POST /notes/ack` | phone | inbox secret |
| `POST /inbox/status`, `DELETE /inbox` | phone | inbox secret |
| `POST /pair/code`, `GET /connections`, `DELETE /connections/:id` | phone | inbox secret |
| `POST /pair/exchange` | agent | none (the pairing code) |
| `GET /inbox`, `POST /inbox/ack`, `GET /agent`, `PATCH /agent` | agent | agent key |

## Basics

### Requirement: Base URL
The relay SHALL be served at `https://api.ramble.watch`, and every path in this spec is relative to it. `https://ramble-transcription-proxy.jpoliachik.workers.dev` SHALL serve the identical API, so agents paired against it keep working.

#### Scenario: Agent probes the base URL
- GIVEN an agent with no credential
- WHEN it sends `GET /` to either host
- THEN it gets `200 {"service": "Ramble relay", "docs": "https://ramble.watch/docs", "llms": "https://ramble.watch/llms-full.txt"}`

### Requirement: Three credentials
Calls other than pairing exchange, inbox creation, App Attest registration and Apple notifications SHALL carry `Authorization: Bearer <credential>`: an inbox secret (`rmbi_…`, the phone), a watch token (`rmbw_…`, the watch) or an agent key (`rmba_…`, an agent). Each is 32 random bytes, and the relay SHALL keep only a SHA-256 hash of it, never a readable copy. `bearer <credential>` and the bare credential SHALL also be accepted.

#### Scenario: Lenient header
- GIVEN a valid agent key
- WHEN it is sent with no `Bearer` prefix
- THEN the call is accepted

### Requirement: 401 means the credential is gone
A missing, unknown or revoked credential SHALL get `401` with `"error": "Invalid or revoked credentials. Send \"Authorization: Bearer <token>\"."`. A valid credential on an endpoint its caller may not use SHALL get `403` with `"reason": "wrong_credential"` and SHALL keep working.

#### Scenario: Agent calls a phone endpoint
- GIVEN a valid agent key
- WHEN the agent calls `GET /connections`
- THEN the response is `403` with `"reason": "wrong_credential"`
- AND its next `GET /inbox` succeeds

### Requirement: Errors are JSON with a stable reason
Every error SHALL be `{"error": "<sentence>"}`, plus `"reason": "<code>"` wherever a client acts on the kind of error. Bodies SHALL be read as JSON whatever their `Content-Type`, except note uploads, which are raw audio. A wrong method on an existing path SHALL get `405` naming the right method and linking https://ramble.watch/docs.

#### Scenario: Wrong method
- GIVEN the path `/inbox/ack`
- WHEN it is called with `GET`
- THEN the response is `405` and the error says to use `POST`

### Requirement: Fail closed
When the relay cannot check a credential, a count, an entitlement or a limit, it SHALL answer `503` with `"reason": "unavailable"` and accept, store and count nothing. Production SHALL honor no developer bypass of any check.

#### Scenario: Database unreachable during an upload
- GIVEN the free-note count can't be read
- WHEN the watch uploads a note
- THEN the response is `503`, nothing is stored or counted, and the watch keeps its audio

## Phone setup

### Requirement: App Attest registration
`POST /attest/challenge` SHALL return `{"challenge"}`, usable once within 5 minutes. `POST /attest` with `{"keyId", "attestation", "challenge"}` SHALL return `200 {"status": "ok"}` only when the attestation chains to Apple's App Attest root, comes from the production App Attest environment, and its app identity hash equals SHA-256 of `SW6VLKWS7Q.dev.goodloop.Ramble`. Any failure, including being unable to check the root, SHALL get `403`.

#### Scenario: Another developer's app, or a development attestation
- GIVEN a valid attestation from an app with a different team or bundle ID, or from the App Attest development environment
- WHEN it is registered with the production relay
- THEN the response is `403` and nothing is stored

### Requirement: Registered keys are never overwritten
Registering a known key ID with the same public key SHALL return `200` and change nothing; with a different public key it SHALL get `409` with `"reason": "key_exists"`.

#### Scenario: Overwrite attempt
- GIVEN a registered key ID
- WHEN it is registered with another public key
- THEN the response is `409` and the stored key is unchanged

### Requirement: Creating an inbox
`POST /inboxes` SHALL require `X-App-Attest-Key-Id` and `X-App-Attest` (an assertion over the exact body, which may be empty) and return `201 {"inbox_secret": "rmbi_…", "account_token": "<UUID>"}`. A missing assertion SHALL get `403` "App attestation required"; a failing one, or one reusing a counter, `403` "App attestation failed". After that, only the inbox secret is checked.

#### Scenario: Free inbox breaker tripped
- GIVEN the daily cap on free inboxes or the free-tier audio-hours breaker has tripped
- WHEN a phone creates an inbox
- THEN the response is `503` with `"reason": "unavailable"`, no inbox is made, and the operator is alerted ([transcription.md](transcription.md))

## Account and purchase

### Requirement: Account state
`GET /account` SHALL return:
`{"unlocked", "free_notes_total": 25, "free_notes_remaining", "fair_use": {"used_hours", "limit_hours", "resets_at", "near"} | null}`, plus `"account_token"` for the phone. `fair_use` is `null` until a purchase is bound. Meaning and thresholds: [subscription.md](subscription.md).

#### Scenario: Close to fair use
- GIVEN an unlocked inbox whose purchase used 41 of its 50 hours this month
- WHEN the phone reads `GET /account`
- THEN `fair_use` is `{"used_hours": 41, "limit_hours": 50, "resets_at": "2026-12-01T00:00:00.000Z", "near": true}`

### Requirement: Submitting a purchase
`POST /entitlement` with `{"signed_transaction": "<JWS>"}` or, for early buyers, `{"app_transaction": "<JWS>"}` SHALL return `200` with the `GET /account` body once the record is verified: signature chained to Apple's root CA, bundle ID `dev.goodloop.Ramble`, not revoked or refunded, not Sandbox or Xcode on production. A transaction SHALL be for the unlock product; the old subscription `dev.goodloop.ramble.premium.monthly2` SHALL be accepted only as early-buyer proof ([subscription.md](subscription.md)). Re-sending a bound record SHALL return `200` and change nothing.

#### Scenario: Forged or refunded record
- GIVEN a self-signed JWS, a refunded transaction, or a Sandbox record sent to production
- WHEN it is submitted
- THEN the response is `403` with `"reason": "invalid_transaction"` and the inbox stays locked

### Requirement: Purchases are bound to inboxes
A first-time unlock purchase SHALL be accepted only when its app account token equals this inbox's `account_token`. A restored purchase may carry another inbox's token. A purchase SHALL unlock at most 5 inboxes, counting only inboxes that uploaded a note in the last 90 days, keyed on the original transaction ID (or the app transaction ID for early buyers). Family-shared purchases SHALL NOT unlock.

#### Scenario: Purchase made for another inbox
- GIVEN a first-time purchase whose account token belongs to inbox A
- WHEN inbox B submits it as its own purchase
- THEN the response is `403` with `"reason": "wrong_account"`

#### Scenario: Sixth active inbox
- GIVEN one purchase bound to 5 inboxes that all uploaded in the last 90 days
- WHEN a sixth inbox submits it
- THEN the response is `403` with `"reason": "too_many_inboxes"`

### Requirement: Apple refund notifications
`POST /appstore/notifications` SHALL accept App Store Server Notifications (version 2) whose signature chains to Apple's root CA and whose environment matches the relay's, answer `200`, and remove the unlock from every inbox bound to a purchase Apple reports as refunded or revoked. Any other body SHALL get `400` and change nothing.

#### Scenario: Refund
- GIVEN a purchase bound to 2 inboxes
- WHEN Apple sends a signed refund notification for it
- THEN both inboxes read `"unlocked": false`

### Requirement: Transcription settings
`GET /settings` and `PUT /settings` with `{"language": "<ISO-639-1>" | null, "remove_filler_words": <bool>, "vocabulary": "<up to 900 characters>"}` SHALL read and replace the inbox's options. `PUT` returns the stored settings; a bad field gets `400`. When they take effect and what they do: [transcription.md](transcription.md).

#### Scenario: Too much vocabulary
- GIVEN 901 characters of vocabulary
- WHEN the phone sends `PUT /settings`
- THEN the response is `400` and the stored settings are unchanged

### Requirement: Watch token
`POST /watch-token` with `{"replaces": "<the watch's previous token>"?}` SHALL return `201 {"watch_token": "rmbw_…"}`, revoke the token named in `replaces` and any other watch token of the inbox, so an inbox has at most one. `DELETE /watch-token` SHALL revoke it and return `200 {"revoked": <0 or 1>}`. Neither SHALL touch agent connections. When the phone calls them: [watch.md](watch.md), [phone.md](phone.md).

#### Scenario: Phone reinstalled
- GIVEN the watch holds a token for the inbox of a previous install
- WHEN the reinstalled phone mints a token with that one as `replaces`
- THEN the old token gets `401` from then on

## Notes

### Requirement: Note upload request
`PUT /notes/:id` SHALL take the note's UUID in the path (any case, returned uppercase), the raw recording as the body with `Content-Type` `audio/mp4`, `audio/m4a`, `audio/x-m4a` or `audio/aac`, a `Content-Length`, and `X-Ramble-Recorded-At: <ISO 8601 with offset>`. Note IDs SHALL be scoped to the inbox. The note's `source` SHALL be `"watch"` or `"phone"` according to the credential that uploaded it. Any duration the client sends SHALL be ignored.

#### Scenario: Same UUID in two inboxes
- GIVEN inbox A holds note `6F1C…`
- WHEN inbox B uploads a note with the same ID
- THEN B's note is accepted as its own, and neither inbox can see the other's

### Requirement: Upload acceptance
The relay SHALL answer success only after the audio is fully stored, and SHALL create the note only then. A first upload SHALL get `201` with the note, and with `"status": "done"` if the transcript is ready within 8 seconds of the audio being stored, else `"status": "transcribing"`. Clients SHALL allow at least 30 seconds for the response. Transcription continues if the client disconnects.

#### Scenario: Short note
- GIVEN the inbox may transcribe
- WHEN the watch uploads a 10-second note
- THEN the response is `201` with `"status": "done"` and the transcript

### Requirement: Upload limits
The relay SHALL refuse, storing and counting nothing: a body over 20 MB (`413`, `"reason": "too_large"`); audio whose container says it is longer than 61 minutes (`413`, `"reason": "too_long"`); no `Content-Length` (`411`); body bytes differing from `Content-Length`, an empty body, or a missing or invalid recorded time (`400`); a recorded time more than 5 minutes in the future (`400`, `"reason": "recorded_in_future"`); a non-audio type (`415`); and a body not finished within 10 minutes (`408`).

#### Scenario: Watch clock far ahead
- GIVEN a watch whose clock is an hour fast
- WHEN it uploads a note
- THEN the response is `400` with `"reason": "recorded_in_future"`

### Requirement: Upload idempotency
The note UUID SHALL be the idempotency key within an inbox. A repeated upload of an accepted ID SHALL be answered `200` with the note's current state before the body is read, and SHALL store and count nothing. Concurrent uploads of one ID SHALL produce one note, counted once.

#### Scenario: Lost response
- GIVEN a watch upload was accepted but the response never arrived
- WHEN the watch uploads the same note again
- THEN the response is `200` with the current status, and the free-note count is unchanged

### Requirement: Held uploads
An upload the inbox may not transcribe SHALL get `402`, and nothing SHALL be kept or counted: `{"reason": "free_notes_used", "free_notes_remaining": 0}` when out of free notes and not unlocked, or `{"reason": "fair_use"}` with `Retry-After` set to the seconds until the fair-use reset. The device keeps its audio. Meaning and copy: [subscription.md](subscription.md).

#### Scenario: Out of free notes
- GIVEN 25 notes accepted and no purchase
- WHEN note 26 is uploaded
- THEN the response is `402` with `"reason": "free_notes_used"`
- AND after `POST /entitlement` succeeds, the same upload gets `201`

#### Scenario: Two devices race for the last free note
- GIVEN one free note left
- WHEN the phone and the watch each finish an upload at the same moment
- THEN one gets `201`, the other `402`, and the refused audio is not kept on the relay

### Requirement: The note shape
Note responses SHALL use:
`{"id", "source", "status": "transcribing" | "done" | "failed", "result", "recorded_at", "received_at", "duration", "transcript", "transcript_cleared"}`.
When done, `result` is `"transcript"` or `"no_speech"`; when failed, `"audio_rejected"` (no provider could transcribe the audio) or `"retries_exhausted"` (it kept failing until the retry window ended); otherwise `null`. `duration` is seconds as measured by the relay, `null` until done. `transcript` is the text when `result` is `"transcript"`, `""` for `"no_speech"`, otherwise `null`. `recorded_at` is exactly as the device sent it, offset included; times the relay produces are ISO 8601 UTC with milliseconds. Meaning: [transcription.md](transcription.md).

#### Scenario: Silent note
- GIVEN a note in which no speech was detected
- WHEN it is read
- THEN `status` is `"done"`, `result` is `"no_speech"` and `transcript` is `""`

### Requirement: Reading a note by ID
`GET /notes/:id` SHALL return `200` with the note. The phone SHALL read any note in its inbox; a watch token SHALL read only notes uploaded with a watch token of that inbox. Any other ID SHALL get `404`. Once its copy for the person's devices is gone, the note SHALL read `"transcript": null, "transcript_cleared": true` for 30 more days, then `404`.

#### Scenario: Watch asks for a phone note
- GIVEN a note recorded on the phone
- WHEN the watch reads its ID
- THEN the response is `404`

### Requirement: Copy kept for the person's devices
A note's transcript SHALL stay readable by the person's devices until the phone has acked it and, for a watch note, the watch has read it as done; and at most 30 days after it is ready. Meaning: [delivery.md](delivery.md).

#### Scenario: Phone acks before the watch looks
- GIVEN the phone acked a watch note
- WHEN the watch first reads it
- THEN it gets the transcript, and later reads show `"transcript_cleared": true`

### Requirement: Phone lists and acks notes
`GET /notes` (phone) SHALL return `{"notes": [...], "next": <cursor> | null}`: every note in the inbox, from either device and in any status, that the phone has not acked, oldest accepted first, 50 per page; `GET /notes?after=<cursor>` returns the next page. This lets the phone learn of a watch note before the watch reports it. `POST /notes/ack` with `{"ids": [up to 500 UUIDs]}` SHALL mark each listed done or failed note as acked by the phone and return `{"acked": <n>, "not_final": [ids]}`; notes still transcribing stay unacked and are listed in `not_final`; unknown or already acked IDs are ignored; agent copies are unaffected.

#### Scenario: Watch note the phone hasn't heard of
- GIVEN the watch uploaded a note while out of reach of the phone
- WHEN the phone calls `GET /notes`
- THEN the note is listed with `"source": "watch"` and its status

#### Scenario: Ack too early
- GIVEN a note still transcribing
- WHEN the phone acks it
- THEN it is in `not_final` and stays in `GET /notes`

## Agents and pairing

### Requirement: Pairing codes
`POST /pair/code` (phone) SHALL return `201 {"code", "expires_at"}`: 12 characters from `23456789ABCDEFGHJKMNPQRSTVWXYZ`, shown as `XXXX-XXXX-XXXX`, single-use, valid 10 minutes. Asking again SHALL cancel the previous code. With 10 agents connected it SHALL get `409` with `"reason": "too_many_agents"`.

#### Scenario: Second code
- GIVEN an unused code
- WHEN the phone asks for another
- THEN the first code no longer exchanges

### Requirement: Pairing exchange
`POST /pair/exchange` with `{"code", "request_id", "name"?}` and no credential SHALL return `201 {"token": "rmba_…"}` and create one connection. `request_id` is a random string of 16–64 characters chosen by the agent; `name` is optional, 1–40 characters, and an invalid name is dropped without failing. Codes SHALL match ignoring case, spaces and dashes. An unknown, used or expired code SHALL get `400` with `"error": "Invalid or expired pairing code. Ask the user for a new one in the Ramble app."`. Which notes the connection receives: [delivery.md](delivery.md).

#### Scenario: Retried exchange
- GIVEN an exchange succeeded but the response was lost
- WHEN the agent retries with the same code and `request_id` within the code's 10 minutes
- THEN it gets `200` and the same key

#### Scenario: Someone else replays the code
- GIVEN a code already exchanged
- WHEN it is sent with a different `request_id`
- THEN the response is `409` with `"reason": "code_used"`, and no key is returned

### Requirement: Connections
`GET /connections` (phone) SHALL return `{"connections": [{"id", "name", "created_at", "last_pull_at", "pending", "hook"}]}`, where `pending` counts that agent's unacked copies and `hook` is `null` or `{"last_ping_at", "last_status"}`; hook URLs and headers SHALL never go to the phone. `DELETE /connections/:id` SHALL revoke that agent's key, delete its copies and return `{"status": "disconnected"}`, or `404` for an ID not in this inbox.

#### Scenario: Disconnect
- GIVEN a connected agent with 3 copies waiting
- WHEN the phone disconnects it
- THEN its next pull gets `401` and the 3 copies are gone

### Requirement: Agent pull
`GET /inbox` (agent) SHALL return `{"items": [{"id", "recording_id", "created_at", "received_at", "duration", "transcription"}], "has_more"}`: only that agent's copies, oldest first, up to 50. `id` is an integer, `created_at` is the recorded time as sent, `received_at` is when the relay accepted the audio, and `duration` is relay-measured seconds. Unacked items SHALL come back on every pull.

#### Scenario: Nothing waiting
- GIVEN no copies for this agent
- WHEN it pulls
- THEN the response is `200 {"items": [], "has_more": false}`

### Requirement: Agent ack
`POST /inbox/ack` (agent) with `{"ids": [1–500 integers]}` SHALL delete those of the agent's own copies and return `{"deleted": <n>}`; IDs gone or not the agent's count as nothing; any other body gets `400`. Unacked copies SHALL be deleted 30 days after they are made.

#### Scenario: Someone else's item
- GIVEN item 41 belongs to another agent
- WHEN this agent acks 41
- THEN the response is `{"deleted": 0}` and item 41 remains

### Requirement: Delivery status
`POST /inbox/status` (phone) with `{"recording_ids": [1–100 note IDs]}` SHALL return `{"recordings": [{"recording_id", "copies", "waiting", "picked_up", "removed", "first_picked_up_at"}], "missing": [ids]}`: agent copies made, still waiting, acked, and removed unread (expired, deleted, or agent disconnected), and the first ack time or `null`. IDs not in this inbox SHALL be listed only in `missing`. States shown from these: [delivery.md](delivery.md).

#### Scenario: Removed unread
- GIVEN a note copied to one agent, which was disconnected before pulling
- WHEN the phone asks
- THEN it gets `"copies": 1, "waiting": 0, "picked_up": 0, "removed": 1, "first_picked_up_at": null`

### Requirement: Agent name and wake-up hook
`GET /agent` SHALL return `{"name", "hook": null | {"url", "header_names", "last_ping_at", "last_status"}}`, never header values. `PATCH /agent` with `{"name"?, "hook"?: {"url", "headers"} | null}` SHALL update them and return the same shape; setting a hook sends one test ping (`"event": "ramble.test"`) and reports its HTTP status (`0` = no response); `"hook": null` removes it. A hook SHALL be `https://` with a public hostname, at most 8 headers and 4 KB, none of `Host`, `Content-Type`, `Content-Length`, `Connection`, `Transfer-Encoding`, `User-Agent`, `Cookie`; otherwise `400`. Hook headers SHALL be stored only encrypted; when encryption is unavailable, setting a hook gets `503`.

#### Scenario: Private hook URL
- GIVEN a hook URL of `https://192.168.1.5/run` or `https://box.local/run`
- WHEN the agent sets it
- THEN the response is `400`

### Requirement: Wake-up pings
When a copy is made for an agent with a hook, the relay SHALL POST `{"event": "ramble.notes_waiting", "text", "pull_url"}` with the agent's headers and `User-Agent: Ramble-Relay/1 (+https://ramble.watch/docs)`, once, with a 5-second timeout and no redirects, after checking that the hostname resolves to a public address. No further ping SHALL go out until the agent pulls or 10 minutes pass. Pings SHALL never carry transcript text.

#### Scenario: Hostname turns private
- GIVEN a hook whose hostname resolved publicly when it was set
- WHEN it resolves to a private address at ping time
- THEN no ping is sent and `last_status` is `0`

## Deleting

### Requirement: Delete waiting notes
`DELETE /inbox` (phone) SHALL delete every agent copy still waiting in the inbox and return `{"deleted": <n>}`. It SHALL NOT delete the copy for the person's devices, notes still transcribing, agent connections, the watch token, the free count or the unlock. Meaning: [delivery.md](delivery.md).

#### Scenario: Unpulled watch note survives
- GIVEN a watch note the phone hasn't pulled, and its agent copy waiting
- WHEN the phone calls `DELETE /inbox`
- THEN the agent copy is gone, and `GET /notes` still lists the note with its transcript

## Limits

### Requirement: Rate limits
Over these limits the relay SHALL answer `429` with `{"reason": "rate_limited"}` and `Retry-After` in seconds, and change nothing:

| What | Limit |
|---|---|
| `POST /attest/challenge` | 20 per hour per network address |
| `POST /attest` | 5 key registrations per day per network address |
| `POST /inboxes` | 3 per day per App Attest key, 20 per hour per network address |
| `POST /pair/code` | 10 per hour per inbox |
| `POST /pair/exchange` | 100 failed attempts per hour per network address |
| `PUT /notes/:id` | 120 per hour and 500 per day per inbox, phone and watch together; repeats of an accepted ID don't count |
| Phone and watch reads (`GET /notes…`, `POST /notes/ack`, `POST /inbox/status`, `GET /account`) | 120 per minute per credential |
| `GET /inbox`, `POST /inbox/ack`, `GET /agent` | 60 per minute per agent key |
| `PATCH /agent` | 10 per hour per agent key |
| `POST /entitlement`, `PUT /settings` | 20 per hour per inbox |
| `POST /watch-token` | 10 per day per inbox |

When failed pairing exchanges across all addresses exceed 1,000 in an hour, every exchange SHALL get `503` for the rest of that hour and the operator SHALL be alerted. Network addresses SHALL be used only by the limiter for its window, never stored with notes or logged.

#### Scenario: Agent checking too often
- GIVEN an agent pulling every second
- WHEN it passes 60 calls in a minute
- THEN it gets `429` with `Retry-After`, and its key still works afterwards

### Requirement: Logs
Relay logs SHALL never contain request bodies, transcript text or audio, SHALL record device identifiers only as hashes, and SHALL keep at most 200 characters of a provider error body.

#### Scenario: Provider error
- GIVEN a provider returns a 5 KB error body
- WHEN the relay logs the failure
- THEN at most its first 200 characters are logged, with the hashed device ID

## Retired paths answer 410

### Requirement: Out-of-date clients are told to update
`POST /transcribe`, `POST /inbox` and `GET /analytics` SHALL answer `410` with `"error": "This version of Ramble is out of date. Update Ramble from the App Store."`, and SHALL transcribe, queue or reveal nothing.

#### Scenario: Out-of-date app sends text
- GIVEN an out-of-date Ramble app
- WHEN it sends `POST /inbox` with a transcript
- THEN the response is `410` and nothing is queued for any agent
