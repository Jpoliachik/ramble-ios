# Connector directory listings

What every connector directory asks for, for Ramble's MCP connector (`https://api.ramble.watch/mcp`, behavior in `specs/connector.md`). Each directory's own submission steps change often, so they live in its current docs, not here.

## Shared pieces

- **Reviewer sign-in:** the review code (Worker secret `REVIEW_CODE`, `proxy/README.md`). It signs in only to the review inbox, which holds five sample notes that come back once all are marked handled. Give it only in directory review forms.
- **Domain checks:** `OPENAI_APPS_CHALLENGE` and `GOOGLE_CONNECTED_APPS_TOKEN` Worker secrets, served at `/.well-known/openai-apps-challenge` and `/.well-known/google-connected-apps`.
- **Icons:** `https://ramble.watch/icon-512.png`, `icon-256.png`, `icon-64.png` (and `ramble-icon-light.png`, 1024).
- **URLs:** website `https://ramble.watch`, docs `https://ramble.watch/docs`, privacy `https://ramble.watch/privacy`, terms `https://ramble.watch/terms`, support `https://ramble.watch/support` (support@ramble.watch).

## Listing copy

- **Name:** Ramble
- **One-liner:** Voice notes from your Apple Watch, ready for your agent.
- **Short (100 max):** Voice notes from Apple Watch and iPhone, ready for your agent to read and mark handled.
- **Description:** Ramble turns what you say into your watch or iPhone into a transcript your agent can pick up. Say it and let it go: no reply to wait for, no signal needed. Your agent lists your new notes, reads the ones it needs, and marks them handled. Ramble keeps no archive: transcripts are deleted once handled, or after 30 days.
- **What users need:** the Ramble app on iPhone (Apple Watch optional). Sign in by pasting the pairing code from Settings → Your agent → Connect.
- **Category:** Productivity (also: Notes).
- **Reads or writes:** reads notes; one write, `mark_handled`, which drops the connector's copy of a transcript. The note stays in the app.
- **Example prompts:**
  1. What did I ramble about today?
  2. Turn my new Ramble notes into a to-do list.
  3. Read my latest Ramble note and mark it handled.

Never mention the price, the unlock or upgrades in a listing description or tool output (OpenAI §5.1).

## Reviewer instructions (paste into each form)

> Ramble has no accounts. Its sign-in page asks for a pairing code from the Ramble iPhone app. For review, paste this review code instead: `<REVIEW_CODE>`. It can be used any number of times and signs in to a demo inbox with five sample notes. Marking all five handled brings them back, so every tool can be tried again. The code is entered on Ramble's own sign-in page; it is not a one-time password for another service, and the connector never asks for codes in chat.

## Test cases (ChatGPT asks for 5 positive, 3 negative)

Positive:
1. "What are my new Ramble notes?" → `list_new_notes` → five notes, newest "Book the dentist for Thursday afternoon…".
2. "Read my Ramble note about the dentist." → `list_new_notes`, `get_note` → the full transcript.
3. "Make a grocery list from my Ramble notes." → `list_new_notes`, `get_note` → oat milk, eggs, spinach, coffee beans, dinner for Friday.
4. "Mark my dentist note as handled." → `mark_handled` (asks to confirm) → `handled: true`; it no longer appears in the list.
5. "What did I say about Sam and the Q3 plan?" → `list_new_notes`, `get_note` → send the draft by Monday, ask who owns the budget.

Negative:
1. "Record a new voice note for me." → no tool; Ramble notes are recorded on the watch or iPhone.
2. "Delete all my notes in the Ramble app." → no tool; the connector can't delete notes in the app.
3. "What's the weather in Paris?" → no Ramble tool.

## MCP Registry `server.json`

```json
{
  "$schema": "https://static.modelcontextprotocol.io/schemas/2025-12-11/server.schema.json",
  "name": "watch.ramble/ramble",
  "title": "Ramble",
  "description": "Voice notes from Apple Watch and iPhone, ready for your agent to read and mark handled.",
  "version": "1.0.0",
  "websiteUrl": "https://ramble.watch/docs",
  "icons": [{ "src": "https://ramble.watch/icon-512.png", "mimeType": "image/png", "sizes": ["512x512"] }],
  "remotes": [{ "type": "streamable-http", "url": "https://api.ramble.watch/mcp" }]
}
```

Versions can't be edited once published: any change needs a new `version`. The signing key never goes in the repo.
