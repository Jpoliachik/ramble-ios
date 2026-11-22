# The note record

## Purpose
The one shape a Ramble note has wherever an agent or automation receives it: the relay's agent inbox, the MCP tools and events, and the iPhone's webhook. It lets agents store, route and compare notes from any of those paths without translating between them. Each surface's own contract is in [relay-api.md](relay-api.md), [connector.md](connector.md) and [delivery.md](delivery.md).

## Requirements

### Requirement: One record, every agent surface
A note SHALL appear to agents and automations as this JSON object, the note record:

| Field | Value |
|---|---|
| `type` | always `"ramble.note"` |
| `version` | always `1` for this shape |
| `id` | the note's id: a UUID, uppercase; notes from old builds may carry other ids. The same note has the same `id` on every surface |
| `source` | `"watch"` or `"phone"`, the device that recorded it; `null` when unknown (notes delivered by old builds) |
| `recorded_at` | when recording started, ISO 8601 exactly as the recording device sent it, with its UTC offset |
| `received_at` | when Ramble's server accepted the audio, ISO 8601 UTC with milliseconds; `null` when the iPhone doesn't know it yet |
| `duration_seconds` | the recording's length in seconds |
| `transcript` | the full transcript text |

Where a surface carries no text, the record SHALL be sent without `transcript` and is otherwise identical. Where it appears: `GET /inbox` items carry it as `note` ([relay-api.md](relay-api.md)); `get_note` returns it and `list_new_notes` lists it without `transcript` ([connector.md](connector.md)); the `note_received` event's `data` is it without `transcript` ([connector.md](connector.md)); the iPhone's webhook carries it as `note` ([delivery.md](delivery.md)). Wake-up hook pings carry no note ([delivery.md](delivery.md)).

#### Scenario: The same note, two paths
- GIVEN a watch note recorded at 2026-11-01T14:00:00-05:00, 42 seconds long, delivered to an agent that both pulls `GET /inbox` and uses the MCP connector
- WHEN the agent reads it both ways
- THEN both records have `type` `"ramble.note"`, `version` `1`, the same `id`, `source` `"watch"`, `recorded_at` `2026-11-01T14:00:00-05:00`, the same `received_at` and `duration_seconds` `42`
- AND the `GET /inbox` item still has its `id`, `recording_id`, `created_at`, `received_at`, `duration` and `transcription` fields alongside `note`

#### Scenario: A note from an old build
- GIVEN an old build delivered a transcript with text `POST /inbox`
- WHEN the agent reads it
- THEN its record has `source` `null`

#### Scenario: An event without the text
- GIVEN a ChatGPT connector subscribed to `note_received`
- WHEN a note lands
- THEN the event's `data` is the note record with every field but `transcript`

### Requirement: Stable within a version
Within `version` 1, fields SHALL only be added, never renamed, removed, or given another meaning or type. A change that would break that SHALL use a new `version`. Agents SHOULD ignore fields they don't know. The surfaces' older fields (`recording_id`, `created_at`, `duration`, `transcription` and the like) SHALL keep working alongside the record.

#### Scenario: An agent written against an older shape
- GIVEN an agent that reads `items[].transcription` from `GET /inbox`
- WHEN it pulls
- THEN `transcription` is still there, with the same value as `note.transcript`

### Requirement: Published schema
A JSON Schema (draft 2020-12) of version 1 SHALL be published at `https://ramble.watch/schemas/note-v1.json`, and the agent docs (`/docs`, `llms-full.txt`, the relay's agent guide) SHALL describe the record and link it.

#### Scenario: Validating a record
- GIVEN any note record from any surface above
- WHEN it is validated against `https://ramble.watch/schemas/note-v1.json`
- THEN it passes
