# Ramble specs

The files in this folder say what Ramble does: what the person using it sees, what their agent receives, and what any other system talking to Ramble can rely on. They are the source of truth for behavior. **The code must do what the specs say, and the specs must say what the code does.**

`docs/` explains why and how (design system, brand, sync architecture, App Store copy). `specs/` states what. When both cover a topic, the spec is the contract and the doc is the reasoning behind it.

## What a spec is

A **spec** is a short Markdown file that describes one area of Ramble as it behaves today, from the outside. It is a contract, not an implementation plan.

A **requirement** is one behavior, stated in one or two sentences using SHALL (always) or SHOULD (expected, with stated exceptions). It says what happens, never how it is built.

A **scenario** is one concrete, checkable example of a requirement: GIVEN a starting state, WHEN something happens, THEN what the person or system observes, with AND for extra steps or results. Every requirement has at least one scenario. Edge cases and failures get their own.

**Belongs in a spec:**

- What the person sees, hears, and feels: screens, states, words that carry meaning, haptics, notifications
- What is stored, where, and for how long, and when it is deleted
- What is sent to whom, and what each party can read
- Limits and numbers someone can observe: caps, counts, timeouts, retry behavior, retention
- Errors, and how each one surfaces
- The API contract that agents and other clients rely on: endpoints, auth, request and response shapes, status codes
- Security, privacy, and cost guarantees

**Does not belong in a spec:**

- Class, file, function, or framework names, or Apple API names (those belong in `docs/sync-architecture.md` and similar)
- Step-by-step logic or data structures
- Why a choice was made, history, change logs, plans, or TODOs

Quick test: if the implementation could change without anyone outside noticing, it does not belong in the spec.

## Format

```markdown
# Area name

## Purpose
One to three sentences on what this area covers and who it serves.

## Requirements

### Requirement: Short name
The system SHALL do one observable thing.

#### Scenario: Short name
- GIVEN a starting state
- WHEN something happens
- THEN the observable result
- AND any further result
```

Group related requirements under `##` headings when a spec gets long. Keep the words plain and the scenarios short.

## Index

| Spec | Covers |
|---|---|
| [watch.md](watch.md) | Recording on Apple Watch, the watch home screen and its states, history on the watch, uploading straight to the relay, no notifications, Siri and App Intents on the watch |
| [phone.md](phone.md) | Recording on iPhone, the notes list and note detail, playback, history merged from the watch and the server, onboarding, Settings, Siri and App Intents on the phone |
| [ipad.md](ipad.md) | How the iPhone app differs on iPad: the device's name in copy, no watch setup, readable width |
| [transcription.md](transcription.md) | What happens to uploaded audio on the server: the provider (Groq), formatting options, recording length cap, failures, audio deletion, cost controls, usage monitoring |
| [delivery.md](delivery.md) | Connecting an agent, delivering transcripts to agents and the app, delivery status, wake-up hooks, webhooks, retention and deletion |
| [relay-api.md](relay-api.md) | The relay's HTTP API: device auth, note upload, inbox reads and acks, pairing, rate limits, status codes |
| [connector.md](connector.md) | Ramble as a remote MCP server: OAuth sign-in with the pairing code, the `list_new_notes`, `get_note` and `mark_handled` tools |
| [usage.md](usage.md) | Usage stats kept for the operator: one content-free row per note, the app version each device last sent |
| [purchase.md](purchase.md) | Free notes, the one-time unlock, Restore Purchases, fair use (heavy-use monitoring, suspending a user), existing buyers |

Split a spec when it passes about 300 lines, or when unrelated kinds of change keep landing in it, and update this index.
