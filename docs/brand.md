# Ramble — Brand

## What Ramble is

A watch app that forwards what you say to your agent.

Tap your Apple Watch, talk, and put your arm down. Your iPhone transcribes it, and the transcript goes to your agent, which handles it later. No screen, no reply to wait for. The watch is where you use Ramble. The phone does the transcription, the delivery, and the settings.

It's asynchronous on purpose. Agents pull on a schedule, so a few minutes between talking and the agent acting is normal and fine.

Temporary by design. No accounts. Transcripts pass through the relay and are deleted on delivery. They don't live there.

## Positioning

**Record on your watch. Your agent handles it.**

Ramble is the capture layer for the agent era. People who have a personal agent still need a way to hand it things in the moment: on a walk, in the car, between meetings. Ramble is that hand-off. It feeds agents. It doesn't compete with note apps or assistants, and it doesn't try to be one.

## What makes Ramble different

1. **Watch-first capture.** The Apple Watch is the identity, not a side feature. Tap, talk, done. No phone out, no screen to read.

2. **Agent forwarding with zero setup.** In the app, tap Connect agent and Ramble shows a short pairing code (like `K7QX-MP4D`, single-use, expires in 10 minutes). Tell your agent "I downloaded Ramble, connect it" and paste the code. That's the whole setup. No API keys to copy, no URLs to configure. Today that agent is Muse. More agents later.

3. **Temporary by design.** No accounts. Audio never goes to the relay, and on-device Apple Speech touches no server at all. Transcripts pass through the relay and are deleted the moment your agent acknowledges them. That's the normal path. Anything your agent never picks up is deleted after a hard maximum of 30 days (PLACEHOLDER: 30 or 60 days, Justin to confirm). The window is that long so a transcript isn't lost if your agent has trouble picking it up for a while. Credentials are stored only as hashes. We say exactly what is stored, where, and for how long.

4. **Accurate transcription.** Apple Speech on-device by default, free and touching no server. Optional cloud models for better accuracy in noise, with accents, or when talking fast: Groq Whisper v3 Turbo, Whisper Large v3, Deepgram Nova-3, OpenAI GPT-Transcribe.

5. **Webhooks still work.** Every transcript can POST to any HTTPS endpoint: signed requests, automatic retries, full API docs. The relay is additive.

## Who it's for

- **Agent owners (primary)** — People who already use a personal agent and want a watch that talks to it. They don't want another inbox to check. They want to say the thing and know it landed. Today that means Muse users. People using other agents (ChatGPT, Claude, Grok and so on) are the broader audience we're building toward, but those connections are not shipped. Strategy, not a claim.

- **Transcription enthusiasts** — People who care about accuracy and want the best speech-to-text models as they ship. They'll pay for cloud transcription because clean transcripts matter to them.

- **Automation builders** — Developers and tinkerers who pipe voice into their own stack. The webhook turns Ramble into a voice input for workflows, databases, and custom backends.

All three value clarity. They trust the app because it says plainly what it keeps, where, and for how long, and then deletes it.

## Tagline (drafts, not locked)

- "Record on your watch. Your agent handles it." (current lead)
- "Talk to your watch. Your agent does the rest."
- "Say it once. Your agent takes it from there."

The tagline should convey: (1) the watch, (2) your agent, (3) you don't have to do anything else.

## Tone

- **Calm and direct.** Short sentences. No hype, no startup language, no "AI-powered" selling points.
- **Honest.** Promise reliability, not transformation. Say what the app does, not what it could hypothetically become.
- **Technical when appropriate.** The audience includes developers and tinkerers. Don't dumb things down, but don't gatekeep either.
- **No fear-based privacy marketing.** Don't scare people about other apps. Just state what Ramble does: no accounts, transcripts deleted on delivery, a stated maximum for anything never picked up. Be precise about what is stored, where, and for how long.

## Visual identity

- **Palette:** Clean and warm. Sage/stone/cream tones, anchored by the brand red.
- **Typography:** SF Pro for body/UI, New York serif (system) for headlines and italic accents.
- **Logo:** Simple waveform mark that works at small sizes (watch complication, app icon). The wordmark is "Ramble" in italic serif preceded by the brand-red dot.
- **UI feel:** Minimal, functional, iOS-native. No custom chrome. Let SwiftUI defaults do the work.

### Color tokens

The brand red is the only saturated color in the palette — used for the record button, the wordmark dot, primary CTAs, italic accents in headlines, and selection state. Everything else is neutral.

| Token | Light | Dark | Usage |
|---|---|---|---|
| `brandRed` | `#D7263D` | `#E64458` | Brand red. Record button, wordmark dot, primary CTAs, selection state, italic accents. |
| `brandRedSoft` | `#F5DCDF` | `#3A1E22` | Tinted disc behind onboarding illustrations; soft red badges. |
| `bg` | `#FFFFFF` | `#0F0E0C` | Page background. |
| `surface` | `#F4F2EE` | `#1B1916` | Card / row fill. |
| `ink` | `#141210` | `#F4EFE7` | Primary text. |
| `inkSoft` | `#403B33` | `#C9C2B5` | Body copy. |
| `inkFaint` | `#7A7163` | `#8A8275` | Captions, faint metadata. |
| `hair` | `#E8E5DF` | `#2A2723` | Hairline borders, dashes, separator lines. |

iOS asset names are kebab-case (`brand-red`, `onboarding-bg`, etc.); SwiftUI accesses them via `Color.brandRed` (auto-generated by Xcode) and the `Color.ob*` aliases for the onboarding utility tokens. The website mirrors the brand red as `--color-red-500: #d7263d` in `globals.css`.

## Key messages

### For agent owners
"Tap your watch and talk. Ramble transcribes it on your phone and hands it to your agent, which takes care of it. Connect with a short pairing code. No keys, no setup."

### For transcription enthusiasts
"Apple Speech on-device for free, or pick a cloud model: Groq Whisper, Deepgram Nova-3, OpenAI GPT-Transcribe. Choose the one that fits how you talk."

### For automation builders
"Every transcript can POST to a webhook. Signed requests, automatic retries, full API docs."

### For the privacy-conscious
"No accounts. Audio never goes to the relay. Transcripts wait there only until your agent picks them up, then they're deleted. Anything never picked up is deleted after 30 days at most (PLACEHOLDER), so nothing is lost if your agent has trouble checking in for a while."

## App Store link

https://apps.apple.com/app/id6761857751

## App Store copy

Lives in [`docs/app-store.md`](app-store.md).

## Design principles

1. **Nothing ever gets lost** — Offline-first, persistent queues on watch and phone, clear status at all times: recorded, transcribed, sent, delivered. If someone records a thought on a hike, it reaches their agent when they're back in range. Core promise.
2. **Capture over organization** — Messy input beats no input. Your agent handles the structure.
3. **No accounts, no audio, transcripts held only until delivery** — The relay identifies inboxes, not people. It never receives audio. It keeps transcript text only until your agent acknowledges it, with a hard maximum (30 days, PLACEHOLDER) as a backstop. We may collect anonymous usage counts, never content. The promise is a deletion policy stated precisely.
4. **Pluggable, not opinionated** — Users choose their transcription model, their agent, and their webhook. Don't lock anyone in.
5. **Ship and iterate** — Don't overbuild. Use it, notice what's missing, add that.

## What Ramble is NOT

- Not a note-taking app — it captures voice and delivers text. Your agent or your own system does the rest.
- Not an AI assistant — no built-in LLM features. Ramble feeds your agent; it isn't one.
- Not a chat interface — your agent doesn't reply on your watch. It's a one-way hand-off.

## What NOT to say

- Don't say "AI-powered" — meaningless buzzword in this context
- Don't say "revolutionary", "game-changing", or "seamless"
- Don't compare directly to Voice Memos or other apps
- Don't say "no servers" or "no data on our servers" — the relay is a server. Say what it holds and when it deletes it.
- Don't say "open source", "read the code", or "verify it yourself", and don't mention self-hosting. Development is private. The privacy story is temporary retention, stated precisely.
- Don't promise real-time. Agents pull on a schedule; minutes of delay is normal.
- Don't promise MCP, ChatGPT, Claude, or Grok connections, or end-to-end encryption, until they ship. Muse is the agent that connects today. "More agents later" is the most to say, with no dates.
- Don't headline "works with any agent"
- Don't promise features that aren't shipped
