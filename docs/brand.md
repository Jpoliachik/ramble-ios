# Ramble — Brand

The source of truth for what Ramble stands for and how we talk about it. Use it for the website, the App Store, social posts, release notes, and in-app copy. How Ramble looks and moves lives in [`design.md`](design.md). App Store fields live in [`app-store.md`](app-store.md).

## The belief

Your best thoughts show up when you're away from a screen: on a walk, in the car, at the stove, halfway through a run. Reaching for your phone to save one pulls you out of the moment, and then the phone keeps you.

Ramble lets you keep the thought without leaving the moment. Say it to your watch, let it go, and get back to what you were doing. Your agent picks it up and handles it later.

**Ramble is a mindfulness app that happens to capture voice.** The product is less time on your phone. Capture and delivery are how we get there.

## The name

A ramble is two things, and Ramble is both:

- **A walk with no destination.** The time when thoughts come. Ramble is built for it: phone at home, watch on your wrist.
- **Talking without polishing.** You don't have to compose anything. Say it the messy way it came to you. Your agent tidies it up.

Use both meanings in copy. "Go for a ramble" works. "Just ramble" works. Never use it to mean long or tedious: Ramble is for quick thoughts, said and gone.

## What Ramble is

A watch app that hands what you say to your agent.

Tap your Apple Watch, talk, and put your arm down. Your iPhone transcribes it, and the transcript goes to your agent, which handles it later. No screen to read, no reply to wait for. The watch is where you use Ramble. The phone does the transcription, the delivery, and the settings, and it can stay in your pocket or at home.

## Positioning

**Talk to your watch. Your agent handles it.**

People with a personal agent still need a way to hand it things in the moment. Ramble is that hand-off, and it ends there on purpose: one tap, one thought, no conversation. It feeds your agent. It doesn't compete with note apps or assistants.

## The four promises

Every piece of copy should support at least one of these, and none should undercut them.

1. **Stay in the moment.** A thought takes seconds. Tap, talk, done. Then you're back.
2. **Leave your phone behind.** Your watch is enough. It records with no phone and no signal, and syncs when you're back in range.
3. **Let it go.** Nothing gets lost and nothing pulls you back in. No reply on your wrist. Your agent has it.
4. **Nothing sticks around.** No accounts. Transcripts are deleted once your agent picks them up. We say exactly what's kept, where, and for how long.

## Who it's for

**Primary: people who want less phone in their day and already use a personal agent.** They walk, run, drive, cook, and parent. They have ideas and to-dos at awkward moments, and they're tired of the phone being the only place to put them. They don't want another inbox. They want to say it and know it landed.

**Secondary: builders.** Developers and tinkerers who pipe voice into their own stack via webhook, or who care which transcription model they use. Speak to them on the docs pages, not in the hero.

## Voice

Ramble sounds like a calm friend who respects your time.

- **Calm.** Unhurried. No urgency, no exclamation marks, no countdowns.
- **Short.** Short sentences, short words. If it can be said in five words, use five.
- **Plain.** Say what happens. "Your agent picks it up," not "seamless agent integration."
- **Honest.** Promise reliability, not transformation. Never claim more than the app does today.
- **Warm, not cute.** Friendly and human, without jokes, puns, or emoji in product copy.

### Copy rules

1. **Lead with the moment, then the mechanism.** "On a walk, a thought comes. Tell your watch." before "Ramble transcribes on your iPhone."
2. **Write to "you."** Ramble is "it," never "we" in product copy. "We" is fine for privacy and pricing, where a person is accountable.
3. **Use concrete moments.** A walk, the car, the dentist reminder, oat milk on the list. Real examples beat abstract benefits.
4. **One idea per line.** Headlines are one thought. Body paragraphs are two or three sentences.
5. **Leave space.** Fewer words on the page is part of the brand. Cut before you add.
6. **Watch text is the tightest.** One or two words on the watch, icons and motion before text. See [`design.md`](design.md).
7. **Be exact about privacy.** Say what's stored, where, and for how long. Never vague comfort words.

### Words we like

moment, walk, say it, let it go, back to your day, your agent handles it, messy is fine, leave your phone, quick, quiet, later, picks it up

### Words we avoid

| Avoid | Why | Say instead |
| --- | --- | --- |
| productivity, hustle, crush, 10x, optimize | Ramble is about doing less on your phone, not doing more | "get back to your day" |
| never miss a thing, capture everything | Fear of missing out is the opposite of the brand | "keep the thought" |
| AI-powered, smart, revolutionary, game-changing, seamless | Hype that says nothing | say what it does |
| notes, note-taking | Ramble isn't a notes app; your agent is where things live | "thought," "what you say" |
| instantly, real-time | Agents pick up on their own schedule | "later," "when your agent checks in" |
| ramble on, rambling (as long or tedious) | Undercuts quick capture | "just say it," "messy is fine" |

## Message house

Use these as written, or start from them.

**Tagline:** Talk to your watch. Your agent handles it.

**Short line** (subtitle, social bio): Say it. Your agent handles it.

**Mindful line** (promo text, campaign): Stay in the moment. Leave your phone behind.

**One sentence:** Ramble lets you capture a thought on your Apple Watch and hand it to your agent, so you can stay in the moment and leave your phone behind.

**Short paragraph (~50 words):** Your best thoughts come when you're away from a screen. Ramble keeps them without pulling you back to one. Tap your Apple Watch, say it the messy way it came to you, and get back to your day. Your agent picks it up and handles it. No phone, no reply to wait for.

### By audience

- **Agent owners:** "Tap your watch and talk. Your agent picks it up and takes care of it. Connect with a short code. No keys, no setup."
- **Privacy-minded:** "No accounts. Audio never goes to the relay. Transcripts wait only until your agent picks them up, then they're deleted. Anything never picked up is deleted after 30 days."
- **Builders:** "Every transcript can POST to your own endpoint. Signed requests, automatic retries, full API docs."
- **Transcription:** "Apple Speech on your iPhone, free and private. Optional cloud models when you want more accuracy."

## Facts we can claim

Keep claims inside this list. If it isn't here, check the code before writing it.

- Records on the watch with no phone and no connection, and syncs later.
- Transcribes on the iPhone with Apple Speech by default. Optional cloud models: Groq Whisper v3 Turbo, Whisper Large v3, Deepgram Nova-3, OpenAI GPT-Transcribe.
- Connect an agent with a short single-use pairing code (like `K7QX-MP4D`, expires in 10 minutes). No API keys or URLs.
- Copy says "your agent." Muse is the agent we build and test with, so name it where someone needs to know what's tested, and don't headline "works with any agent."
- No accounts. The relay never receives audio. Transcripts are deleted when the agent picks them up, and after 30 days at most if it never does. Credentials are stored only as hashes.
- Webhooks: signed POST to any HTTPS endpoint, with retries.
- $4.99 once. Optional $2.99/month for cloud transcription. Cloud is never required.

## What not to say

- Don't promise real-time delivery. Minutes of delay is normal and fine.
- Don't say "no servers" or "no data on our servers." The relay is a server. Say what it holds and when it deletes it.
- Don't say "open source," "read the code," or "verify it yourself," and don't mention self-hosting.
- Don't say "no subscriptions ever." The cloud upgrade is optional, not absent.
- Don't claim a cloud model is better for noise or accents. No independent benchmark backs that. "More accurate" is fine.
- Don't promise MCP, ChatGPT, Claude, or Grok connections, speaker labels, or end-to-end encryption until they ship.
- Don't use fear-based privacy marketing or compare directly to other apps.

## What Ramble is not

- **Not a notes app.** It captures voice and delivers text. Your agent or your own system keeps it.
- **Not an assistant.** No built-in LLM. Ramble feeds your agent; it isn't one.
- **Not a conversation.** Your agent doesn't reply on your watch. It's a one-way hand-off, and that's the point.

## Product principles

1. **Nothing ever gets lost.** Offline-first queues on watch and phone, clear status at every step. A thought recorded on a hike reaches your agent when you're back in range.
2. **Capture over organization.** Messy input beats no input. Your agent handles the structure.
3. **Less screen, not more.** Every feature should shorten the time someone spends looking at a device. If it adds a reason to look, question it.
4. **Hold as little as possible.** No accounts, no audio on the relay, transcripts kept only until delivery, with a stated maximum.
5. **Pluggable.** People choose their transcription model, their agent, and their webhook.
6. **Ship and iterate.** Use it, notice what's missing, add that.

## Visual identity

Lives in [`design.md`](design.md): palette (warm neutrals anchored by brand amber), type (SF Pro, New York serif for headlines), the wordmark, motion, and haptics.

## Links

- Website: https://ramble.watch
- App Store: https://apps.apple.com/app/id6761857751
