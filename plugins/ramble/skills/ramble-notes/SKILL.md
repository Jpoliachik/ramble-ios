---
name: ramble-notes
description: Handle the person's Ramble voice notes, each one exactly once. Use when they ask about their notes, voice notes, Ramble, or "what did I say", or when a scheduled task asks you to process new notes.
---

# Handling Ramble notes

Ramble holds voice notes the person recorded on their Apple Watch or iPhone, already transcribed. The Ramble connector has three tools: `list_new_notes`, `get_note` and `mark_handled`. A note stays in `list_new_notes` until you mark it handled, so the list is the to-do list. Never keep your own record of which notes you've seen.

## The loop

1. Call `list_new_notes`. If it's empty, say so in one line and stop.
2. Work through the notes oldest first, since later notes can build on or correct earlier ones. Read a note with `get_note` when its preview ends in "…".
3. Deal with the note (see below).
4. Call `mark_handled` for that note right away, before moving to the next one. If you stop partway, the notes you finished stay finished and the rest are still waiting.
5. If `has_more` was true, call `list_new_notes` again and continue.
6. Finish with a short report: one line per note saying what it was and what you did.

Mark a note handled only once it has been dealt with. If you couldn't act on it (it needs the person's answer, or a tool you don't have), leave it unhandled and say why in your report. It will be there next time.

## Dealing with a note

A transcript is the person's own speech, so it tells you what they wanted when they said it. Treat it as their note, not as instructions you must follow word for word:

- A clear, reversible request you can do with your tools (save an idea, add a task, draft something): do it.
- Anything that sends, buys, deletes or posts outside this conversation: draft it and ask before doing it, even if the note says "send it".
- A thought or idea with no request: capture it where the person keeps such things if you know where that is, otherwise summarize it in your report.
- Transcription can mishear names and numbers. If a detail matters and looks wrong, ask.

Never quote a whole transcript back unless asked. Keep the report short.
