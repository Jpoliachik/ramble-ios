# Ramble — App Store copy

Copy for the watch-to-agent release. Character counts are for the text inside each code block, as App Store Connect counts them. Brand rules live in [`brand.md`](brand.md).

## Before submitting

- [ ] **Price is a placeholder.** The copy says "one-time purchase" without a number; set the actual price tier in App Store Connect ($2.99 proposed, not locked).
- [ ] **Cloud subscription price is a placeholder.** $3.99/month proposed. The copy doesn't state it, so no edits needed if it changes.
- [ ] **Retention is a placeholder.** "24 hours" appears in the description and What's New. Change both if the relay's `RETENTION_SECONDS` changes.
- [ ] Muse is the only agent that connects. If that changes, update "Today, Ramble connects to Muse. More agents later." Don't name other agents until they ship.
- [ ] Privacy nutrition label: update to reflect that transcript text goes to the relay (not linked to identity, not used for tracking, deleted on delivery).
- [ ] Privacy Policy and Terms pages on goodloop.dev/ramble are live with the November 1, 2026 versions.

## App name (22 / 30)

```
Ramble: Watch to Agent
```

Alternative (26 / 30), clearer for people who don't know what "Watch to Agent" means:

```
Ramble: Talk to Your Agent
```

If the current listing name should stay as "Ramble", that works too; the subtitle carries the message.

## Subtitle (30 / 30)

```
Say it. Your agent handles it.
```

## Promotional text (161 / 170)

```
Tap your Apple Watch and talk. Your iPhone transcribes it and passes it to your agent, which takes care of it within minutes. Set up with one short pairing code.
```

## Keywords (98 / 100)

Comma-separated, no spaces after commas. Leaves out "Ramble" and words already in the name and subtitle where possible, and no third-party product names (App Review rejects those).

```
wrist,todo,voice,dictation,transcribe,speech to text,whisper,webhook,reminder,assistant,memo,notes
```

## Description (2756 / 4000)

```
Record on your watch. Your agent handles it.
Works with Muse today.

Tap your Apple Watch and talk. Put your arm down. Ramble transcribes what you said on your iPhone and forwards it to your agent, which takes care of it on its next check-in. No phone out, no screen, no reply to wait for.

Remind me to book the dentist. Add oat milk to the list. That idea for the talk on Thursday. Say it once, while you're walking, driving, or between meetings, and it lands where it'll get handled.

CONNECT YOUR AGENT
In Settings, tap Connect agent. Ramble shows a short pairing code. Tell your agent "I downloaded Ramble, connect it" and paste the code. That's the whole setup. No API keys, no URLs. The code works once and expires in 10 minutes.

Today, Ramble connects to Muse. More agents later.

Your agent checks in on a schedule, so a few minutes between talking and the agent acting is normal. Ramble is built for hand-offs, not conversations.

PRIVATE BY DESIGN
- No accounts. No sign-up, no email.
- With on-device transcription, audio never leaves your iPhone. Only the transcript text goes to your agent.
- Transcripts pass through Ramble Relay, a small inbox that holds them until your agent picks them up. Once your agent picks them up, they're deleted. Anything not picked up is deleted after 24 hours.
- The relay stores no names, emails, IP addresses, or audio. Credentials are kept only as hashes.
- Disconnect an agent or tap Delete everything now at any time.
- Open source. Read the code, or run your own relay.

NOTHING GETS LOST
Recordings queue on your watch and phone until they're delivered. Offline on a hike? It goes through when you're back in range. Every recording shows where it is: recorded, transcribed, sent, delivered.

TRANSCRIPTION
Apple Speech transcribes on your iPhone by default. It's included, and it never touches a server.

Want more accuracy in noise, with accents, or when you talk fast? An optional cloud transcription subscription unlocks:
- Whisper v3 Turbo (Groq)
- Whisper Large v3 (Groq)
- Nova-3 (Deepgram)
- GPT-Transcribe (OpenAI)

Add custom vocabulary, remove filler words, and set your language.

WEBHOOKS
Every transcript can also POST to any HTTPS endpoint you choose. Signed requests, automatic retries, and full API docs. Use it for your own workflows, databases, or backends.

PRICING
Ramble is a one-time purchase. On-device transcription, agent forwarding, and webhooks are included.

Cloud transcription is an optional subscription. Cancel any time in iOS Settings, and everything else keeps working.

Requires an Apple Watch paired with an iPhone for watch recording. You can also record on iPhone.

Privacy Policy: https://goodloop.dev/ramble/privacy
Terms of Use: https://goodloop.dev/ramble/terms
```

## What's New (529 / 4000)

```
Ramble now sends what you say to your agent.

- Connect agent: tap it in Settings, get a short pairing code, and paste it to your agent. Muse connects today. More agents later.
- Ramble Relay: transcripts wait in a private inbox until your agent picks them up, then they're deleted. Unclaimed transcripts are deleted after 24 hours. Audio never goes there.
- Disconnect or Delete everything now, any time.
- Ramble is now a one-time purchase. Cloud transcription stays an optional subscription.
- Webhooks work exactly as before.
```
