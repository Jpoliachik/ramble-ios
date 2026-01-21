# Ramble — Vision Document

## What is this?

A personal voice journaling app that captures daily thoughts through short voice recordings, automatically transcribes them, and extracts meaningful insights. Built for one person (Justin), optimized for his specific workflow and needs.

## The Problem

Justin has always struggled with:

- Remembering what he did, thought, and felt on any given day
- Finding time to journal — writing feels like a chore
- Inconsistent systems — past attempts scattered across apps, formats, and abandoned habits
- Getting value from captured data — even when he does journal, it's hard to look back and find patterns

The insight: talking is easier than writing. A 2-3 minute voice ramble captures more than 20 minutes of reluctant typing ever would.

## The North Star

> At the end of each day, Justin has a rich, searchable, structured record of what he did, discovered, thought about, and how he felt — without it feeling like work.

The app succeeds if:

- Recording feels frictionless (< 3 seconds from intent to talking)
- The output is genuinely useful to look back on
- The habit sticks

## Core Loop

```
Feel like talking → Open app → Tap → Ramble → Done
```

(Behind the scenes: transcribe → extract → store)

Later: Browse past entries → Remember, reflect, spot patterns

## What to Focus On (Iteration Priorities)

### Phase 1: Capture (current)

- Get the recording → transcription → extraction flow working
- Make it fast and reliable
- Actually use it daily and see what's missing

### Phase 2: Habit Formation

- Experiment with reminders/nudges (what time? what trigger?)
- Widget for quick access
- Reduce any friction discovered in Phase 1

### Phase 3: Retrieval & Value

- Make past entries browsable and searchable
- Surface patterns (energy trends, recurring themes)
- Daily/weekly summaries across multiple recordings

### Phase 4: Integration

- Export to Obsidian (via cloud storage + Remotely Save)
- Build knowledge graph connections
- Cross-reference with other data sources

## Design Principles

1. **For Justin, not for "users"** — No need to generalize. Optimize for one person's preferences, workflow, and quirks. If something feels wrong, change it immediately.

2. **Capture over organization** — The biggest failure mode is not capturing at all. Organization can come later. Don't let perfect structure prevent messy input.

3. **LLM-native from the start** — Raw transcripts are valuable, but the real magic is in extraction, summarization, and pattern recognition. Design data formats assuming LLMs will process them.

4. **Plain text wins** — Markdown files are portable, future-proof, and greppable. Avoid proprietary formats or complex databases.

5. **Iterate based on real use** — Don't overbuild. Ship the minimal thing, use it, notice what's missing, add that. Repeat.

## What Success Looks Like

- **1 week**: App works. Justin has recorded 5+ entries. Transcription and extraction feel useful.
- **1 month**: Habit is forming. Justin reaches for the app naturally. Looking back at entries provides genuine value ("oh right, I was thinking about that").
- **3 months**: A meaningful archive exists. Patterns emerge. The data feeds into broader personal knowledge management. Justin can't imagine not having this.

## What This is NOT

- A product for other people (yet)
- A polished, designed experience
- A replacement for deep writing/reflection
- A complete PKM system (it's one input into a larger system)

## Open Questions (to answer through use)

- When is the best time to record? End of day? Multiple times? On-demand only?
- How much extraction is useful vs. noise?
- What prompts/questions help most when starting a ramble?
- Should state tracking (energy, mood, etc.) be explicit prompts or inferred?
- How important is audio playback vs. just reading transcripts?
- What's the right level of structure in the extracted output?
