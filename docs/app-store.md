# Ramble — App Store metadata

This file is the source of truth for the App Store listing. Change the copy here first, then push it to App Store Connect. Muse can do that with the App Store Connect API. Character counts are in brackets after each heading.

Fields marked **TODO: confirm in ASC** haven't been checked against App Store Connect yet. Fill them in from the live listing the next time someone pulls it.

## App information

| Field | Value |
| --- | --- |
| Apple ID | 6761857751 |
| App Store URL | https://apps.apple.com/app/id6761857751 |
| Bundle ID (iOS) | `dev.goodloop.Ramble` |
| Bundle ID (watch) | `dev.goodloop.Ramble.watchkitapp` |
| SKU | TODO: confirm in ASC |
| Primary category | TODO: confirm in ASC (suggest Productivity) |
| Secondary category | TODO: confirm in ASC (suggest Utilities) |
| Age rating | TODO: confirm in ASC |
| Copyright | TODO: confirm in ASC |
| Price | $4.99 one-time |
| In-app purchase | Optional $2.99/month subscription for cloud transcription |

## URLs

| Field | Value |
| --- | --- |
| Marketing URL | https://ramble.watch |
| Privacy Policy URL | https://ramble.watch/privacy |
| Terms of Use (EULA) | https://ramble.watch/terms |
| Support URL | TODO: confirm in ASC (ramble.watch has no support page yet) |

## Name [29 / 30]

```
Ramble: Voice Notes for Watch
```

The brand doc avoids "notes," but the name is the field that ranks most heavily in search, and "voice notes" and "watch" are the words people type. Keep it here for discovery and use the brand voice everywhere else.

## Subtitle [30 / 30]

```
Say it. Your agent handles it.
```

## Keywords [99 / 100]

Commas with no spaces. Don't repeat words that are already in the name or subtitle, because Apple indexes those fields anyway. Don't use competitor or agent brand names, because Apple rejects them.

```
ai,assistant,memo,dictation,transcribe,speech,mindful,wrist,todo,reminder,idea,journal,walk,offline
```

## Promotional text [147 / 170]

You can change this field without a new app version.

```
Go for a ramble and leave your phone behind. Say the thought to your Apple Watch, let it go, and get back to your day. Your agent handles it later.
```

## Description

```
Stay in the moment. Say the thought to your Apple Watch, let it go, and get back to your day. Your agent picks it up and handles it later.

Your best ideas show up on a walk, in the car, halfway through a run. Ramble keeps them without pulling you back to your phone. An idea, a to-do, a reminder. Messy is fine, and there's no reply to wait for. No signal? It waits on your watch and goes out when you reconnect.

SETUP
In Settings, tap Connect agent to get a short code. Tell your agent "I downloaded Ramble, connect it" and paste the code. That's it.

PRIVACY
- No accounts.
- With on-device transcription, audio never leaves your iPhone. Only the text goes to your agent.
- Text is deleted once your agent picks it up, or after 30 days if it never does.
- Disconnect any time.

TRANSCRIPTION
Apple Speech transcribes on your iPhone. An optional upgrade adds cloud transcription for more accurate results.

WEBHOOKS
Ramble can also send each transcript to any HTTPS endpoint.

Ramble is a one-time purchase, with an optional upgrade for cloud transcription. Requires an Apple Watch paired with an iPhone.
```

## Screenshot captions

Short, one thought each, in this order. The first screenshot shows the watch recording, not the phone.

1. Talk to your watch. Your agent handles it.
2. Leave your phone behind.
3. Messy is fine. Just say it.
4. Connect your agent with one code.
5. Deleted once your agent has it.

## What's New (1.1.3)

```
Ramble now hands what you say to your agent. Tap Connect agent in Settings, paste the code to your agent, and start talking. Transcripts are deleted once your agent picks them up. Webhooks work as before.
```

## App Review notes

TODO: confirm in ASC. Include how a reviewer can test Connect agent without their own agent, if that's needed.
