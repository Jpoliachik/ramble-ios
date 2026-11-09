# Usage stats

## Purpose
What Ramble's server keeps to show Justin how Ramble is used and to debug problems: one row per note with no content, and the app version each device last sent. What the person is told about it is in [delivery.md](delivery.md) ("One privacy wording everywhere") and [phone.md](phone.md) ("How privacy works"); the rest of the relay's storage is in [relay-api.md](relay-api.md) and [transcription.md](transcription.md).

## Requirements

### Requirement: One usage row per note
Every inbox SHALL get a random usage ID, separate from its inbox ID. When a note becomes final (`done` or `failed`), the relay SHALL write one usage row for it, keyed by the usage ID and a one-way hash of the note ID, holding: which device recorded it, the recorded-at and accepted times, the time it became final, its length, its result, its attempt and hand-retry counts, whether it used a free note (a failed note never did), its language setting, whether filler-word removal and vocabulary were on, and the app label. A hand retry SHALL rewrite that row, not add one. Usage rows SHALL hold no inbox ID, note ID, audio, transcript text, vocabulary words or agent details, and SHALL be kept indefinitely: deleting a note does not delete its row. Writing a row SHALL never fail or delay the note.

#### Scenario: A watch note is transcribed
- GIVEN the watch uploads a note with `X-Ramble-Client: Ramble/1.3 (142) watchOS/11.5`
- WHEN it is transcribed
- THEN one usage row records it as a watch note with its length, result `transcript` and that label, under the inbox's usage ID
- AND the row holds neither the transcript nor the note ID

#### Scenario: The note is long gone
- GIVEN a note was transcribed and later deleted by the 30-day cleanup
- WHEN Justin queries usage rows
- THEN the note's row is still there

### Requirement: App version per device
The phone and the watch SHALL send `X-Ramble-Client: Ramble/<version> (<build>) <iOS|watchOS>/<os version>` on their relay requests. The relay SHALL keep the latest label from `PUT /notes/:id` and `GET /notes` on the inbox, one for the phone and one for the watch, and on the note for its usage row. A label longer than 80 characters or with non-printable characters SHALL be ignored, and a missing one changes nothing.

#### Scenario: Phone checks in
- GIVEN the phone calls `GET /notes` with `X-Ramble-Client: Ramble/1.3 (142) iOS/26.2`
- WHEN Justin looks at the inbox
- THEN its phone app label reads `Ramble/1.3 (142) iOS/26.2`

#### Scenario: Malformed label
- GIVEN a request sends an `X-Ramble-Client` of 200 characters
- WHEN the relay handles it
- THEN the label is ignored and the inbox keeps the one it had

### Requirement: Usage stats are for the operator only
No endpoint SHALL return usage rows or app labels. Justin reads them directly from the relay's database.

#### Scenario: An agent asks for stats
- GIVEN a connected agent
- WHEN it calls any relay endpoint
- THEN no response contains usage rows or another inbox's app label
