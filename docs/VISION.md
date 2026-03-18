# Ramble — Vision Document

## What is this?

Voice-to-text capture. Tap, talk, get a transcript. That's the whole thing.

Ramble is an iOS + watchOS app for capturing thoughts by voice. It records, transcribes, and stores a history of everything you say. The value is speed, reliability, and a searchable text log of your spoken thoughts.

## The Problem

Typing is slow. Thoughts are fast. By the time you open a notes app and start typing, you've already lost half of what you wanted to say — or you just don't bother.

Voice capture solves this, but existing solutions are either unreliable, require too much setup, or lock your data into a platform.

## The North Star

> Quick tap → record → transcript appears → always findable. Nothing ever gets lost.

The app succeeds if:

- Recording starts in < 3 seconds from intent
- Transcription is fast and accurate
- The transcript log is easy to browse and copy from
- It works from phone, watch, CarPlay, and Siri — wherever you are
- Nothing ever gets lost, even offline

## Core Loop

```
Have a thought → Tap record → Talk → Stop → Transcript appears
```

Later: Browse the log → Find what you said → Copy/paste it wherever you need it

## Who is this for?

Ramble is growing toward a product. Primary audience:

- **Anyone who thinks faster than they type** — capture ideas, notes, reminders, reflections by voice
- **People who are living, not sitting at a desk** — driving, walking, running, cooking, carrying things. Moments where you can't type but you can talk.
- **No technical knowledge required** — should work out of the box
- **Privacy-conscious** — no login, no user data stored on servers

## Brand & Positioning

Ramble is a **lifestyle brand**, not an indie dev project.

The core feeling: you're out in the world, living your life, and your thoughts don't get lost. The app disappears — what remains is the freedom to capture anything, anywhere.

**Brand position:** Capture while living. Not at your desk. Not in front of a screen. Out there.

**Marketing approach:** All content is outdoors. Videos of recording while walking, on a run with the watch, driving with CarPlay, hiking. Never indoors. The brand lives where the user lives — outside, in motion, hands busy.

**Visual direction:** Natural color palette. Soft, outdoorsy. Think earth tones, muted greens, warm neutrals. Not techy, not startup-blue. The aesthetic says "go outside" not "open another app."

**Channel:** Dedicated Instagram. Make it legit — not personal account, not dev log. A proper brand presence that evokes the lifestyle.

See `docs/BRAND.md` for full brand guide.

## Architecture

Record → Transcribe (on-device or via proxy) → Store locally → Optionally POST to webhook.

No login. No accounts. No server-side user data.

**Two selling points:**
1. Quick, easy transcription from any device — phone, watch, CarPlay, Siri. Get a log of your thoughts you can browse and copy from.
2. First app that integrates with AI agents in a generic way. Configure a webhook, POST your transcripts to anything.

Full architecture spec: `docs/spec-architecture.md`

## Roadmap

### Now: Reliability & Core Polish

The capture flow works. Focus is making it **bulletproof**.

**Watch reliability pass (top priority):**
- Offline recording must work without connection
- Sync queue — when connection available, sync everything; never drop a recording
- Watch face status — show pending/syncing queue on watch
- Phone status view — every recording shows exact status at all times

**Bugs:**
- Haptics not firing on record start/stop (code exists but broken)
- Record button layout shift on press
- Screen doesn't auto-update when transcript completes
- Mic input indicator needs work

**Missing:**
- Manual retry button for stuck transcriptions
- Transcript list polish (easy browsing + copy)

### Next: New Surfaces

- **CarPlay support** — record while driving
- **Widget** — quick access from home screen
- **Better onboarding** — non-technical users should be able to set up without help

### Later: Search & Browse

- Full-text search across transcripts
- Timeline browsing

### Future: Distribution

- **Open source release**
- **Business model TBD** — likely: free (BYOK / on-device) + paid (hosted transcription proxy)

## Design Principles

1. **Nothing ever gets lost** — Offline-first, persistent queues, clear status at all times. This is the core promise.

2. **Capture over organization** — Messy input beats no input. Structure comes later.

3. **No user data on servers** — Privacy by architecture. No login, no accounts, no server-side storage.

4. **Pluggable, not opinionated** — Users choose their transcription provider. Webhook for downstream processing. Don't lock anyone in.

5. **Ship and iterate** — Don't overbuild. Use it, notice what's missing, add that.

## What This is NOT

- A note-taking app (it captures voice, gives you text — what you do with it is up to you)
- An AI assistant (no built-in LLM features — webhook is the extensibility model)
- A platform that stores your data (transcripts live on your device)

## Open Questions

- On-device vs. API transcription — what's the right default experience?
- Business model details — how does the paid tier work exactly?
- How much should the app help with organization, or is raw transcript log enough?
