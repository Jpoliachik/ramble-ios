# Ramble — Brand

## What Ramble is

A voice capture app that gives you accurate transcripts and lets you do something with them.

Record a thought while you walk, get a clean transcript, and pipe it into your agent, workflow, or automation. No screen required — put your phone away, talk, and your words become actionable text.

Open source, private by design, no accounts.

## What makes Ramble different

1. **Best-in-class transcription** — Choose from the latest cloud models (Groq Whisper, Deepgram Nova-3, OpenAI GPT-4o Transcribe) or use Apple's on-device speech recognition. Cloud models deliver better accuracy — especially in noisy environments, with accents, or when speaking quickly — and produce cleaner punctuation and formatting. New models get added as they ship.

2. **Webhook-native** — Every transcript can automatically POST to any HTTPS endpoint. Connect Ramble to an AI agent, a Zapier workflow, a Notion database, or your own backend. Capture your thoughts, then do something with them.

3. **Capture on the go** — Record from your Apple Watch or phone without looking at a screen. Walk, think, talk. Your transcript is waiting when you get back. Ramble is built for getting off your phone, not staring at it.

4. **Private by architecture** — No accounts. No login. No user data on our servers. Audio and transcriptions never leave your device unless you choose to send them somewhere. Fully open source — the codebase is the proof.

## Who it's for

- **Automation builders & self-hosters** — Developers, tinkerers, homelabbers, and the r/selfhosted crowd who want to pipe voice into their own stack. The webhook turns Ramble into a voice input device for anything they've built — an AI agent, an n8n or Node-RED flow, Home Assistant, a custom backend on their own server. They value that it's MIT-licensed, runs without an account, and stores nothing on our servers. This is the lead audience: they have somewhere for their thoughts to go, and they need a great microphone for it.

- **Transcription enthusiasts** — People who care about accuracy and want access to the best speech-to-text models as soon as they're available. They'll pay for cloud transcription because clean, reliable transcripts matter to them.

These audiences value privacy and transparency above all. Open source isn't a footnote — it's why they trust the app, and the reason they'll recommend it on Reddit and GitHub.

## Positioning

Ramble is the voice front-end for your stack. Not another note-taking app, not another AI assistant — the capture layer that turns a spoken thought into text and POSTs it straight to whatever system you've already built: an AI agent, an n8n or Node-RED flow, Home Assistant, a Zapier automation, or your own backend on your own server.

The pitch: speak a thought on the go, and it's already where you work — no copy-paste, no app to go back and check. You bring the system; Ramble is the microphone for it.

## Tagline

**Primary:** Voice in. Webhooks out.

Secondary / contextual:
- "Talk to your stack."
- "The microphone for your automations."
- "Your voice, your endpoint."

Retired — do not use: "Voice that goes somewhere," "goes somewhere," "voice that goes anywhere." Too vague; that was the old positioning and it undersold the wedge. Always name the destination (your server, an agent, n8n, Home Assistant, a webhook).

## Tone

- **Calm and direct.** Short sentences. No hype, no startup language, no "AI-powered" selling points.
- **Honest.** Promise reliability, not transformation. Say what the app does, not what it could hypothetically become.
- **Technical when appropriate.** The audience includes developers and tinkerers. Don't dumb things down, but don't gatekeep either.
- **No fear-based privacy marketing.** Don't scare people about other apps. Just state what Ramble does: open source, no user data stored, verify it yourself.

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

### For transcription enthusiasts
"The best speech-to-text models, right when they ship. Groq Whisper, Deepgram Nova-3, OpenAI GPT-4o Transcribe — pick the one that fits. Or use Apple Speech for free, on-device transcription that never leaves your phone."

### For automation builders
"Every transcript can POST to a webhook. Connect Ramble to your agent, your workflow, or your own backend. Signed requests, automatic retries, full API docs."

### For the privacy-conscious
"Open source. No accounts. No user data on our servers. Your audio and transcriptions stay on your device unless you choose to send them somewhere. Don't take our word for it — read the code."

## App Store link

https://apps.apple.com/app/id6761857751

## App Store metadata (ASO)

Discovery strategy: don't fight for "transcribe" / "voice to text" — unwinnable for a new app, and not why Ramble is special. Own the high-intent, low-competition niche instead: voice → webhook → your own stack. Lead the messaging at the r/selfhosted / automation-builder crowd (open source, no account, your own endpoint); let the lower-weight keyword field net the adjacent generic terms.

**Name** (≤30): `Ramble: Voice to Webhook`
**Subtitle** (≤30): `Open-source dictation to API`
**Keywords** (≤100, comma-separated, no spaces, singular — App Store handles plurals and cross-field phrasing):
`selfhost,n8n,zapier,notion,transcribe,speech,agent,automation,gpt,claude,memo,text,audio,recorder`

Alternate keyword swaps for the self-host crowd (lower search volume, higher signal): `homeassistant`, `nodered`, `api`, `opensource`.

### App Store description

> Voice in, webhooks out.
>
> Ramble turns your voice into text and POSTs it straight to your own endpoint — your AI agent, n8n, Node-RED, Home Assistant, Zapier, or any HTTPS webhook. Speak a thought and it's already in your stack.
>
> Open source and private by design. No account. No login. Nothing stored on our servers — audio and transcripts stay on your device unless you choose to send them somewhere. The whole app is MIT-licensed on GitHub. Verify it yourself.
>
> • Free, no account: on-device transcription (Apple Speech) + webhook delivery. No subscription required.
> • Optional cloud models — Groq Whisper, Deepgram Nova-3, OpenAI GPT-4o — for $3.99/month when you want top accuracy.
> • Record from iPhone or Apple Watch with no screen. Walk, talk, done.
> • Signed requests, automatic retries, full webhook API docs.
>
> Built for people who've already built somewhere for their thoughts to go.

## Design principles

1. **Nothing ever gets lost** — Offline-first, persistent queues, clear status at all times. If someone records a thought on a hike, the transcript is there when they get home. Core promise.
2. **Capture over organization** — Messy input beats no input. Structure comes later, somewhere else.
3. **No user data on servers** — Privacy by architecture. Open source proves it. We may collect anonymous usage metrics but never store audio, transcriptions, or anything identifiable.
4. **Pluggable, not opinionated** — Users choose their transcription model. Webhook for downstream. Don't lock anyone in.
5. **Ship and iterate** — Don't overbuild. Use it, notice what's missing, add that.

## What Ramble is NOT

- Not a note-taking app — captures voice, gives you text. What you do with it is your business.
- Not an AI assistant — no built-in LLM features. Webhook is the extensibility model.
- Not a platform — no accounts, no backend, no server-side data.

## What NOT to say

- Don't say "AI-powered" — meaningless buzzword in this context
- Don't say "revolutionary" or "game-changing"
- Don't compare directly to Voice Memos or other apps
- Don't oversell Apple Watch as the primary differentiator (it's a feature, not the identity — show it in a screenshot, don't headline it)
- Don't promise features that aren't shipped
- Don't use "goes somewhere" / "anywhere" — name the destination (your server, an agent, n8n, a webhook). Vague destinations were the old, underperforming positioning.
- Don't lead with the $3.99 subscription — for the open-source / self-host crowd, "free, no account, your own endpoint" is the hook; cloud models are an optional add-on, never the headline.
