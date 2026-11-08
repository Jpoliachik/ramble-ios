# Ramble — App Store metadata

This file is the source of truth for the App Store listing. Change the copy here first, then push it to App Store Connect. Muse can do that with the App Store Connect API. Character counts are in brackets after each heading.

Fields marked **TODO: confirm in ASC** haven't been checked against App Store Connect yet. Fill them in from the live listing the next time someone pulls it.

Pricing words follow `specs/purchase.md` ("What Ramble says about price"): the price story is "Free to download. 25 notes free, then $14.99 once." Never "trial", "unlimited", "premium", "Subscribe", or a price per month. Privacy words follow `specs/delivery.md` ("One privacy wording everywhere"). No on-device transcription claims, and no open-source claims.

## App information

| Field | Value |
| --- | --- |
| Apple ID | 6761857751 |
| App Store URL | https://apps.apple.com/app/id6761857751 |
| Bundle ID (iOS) | `dev.goodloop.Ramble` |
| Bundle ID (watch) | `dev.goodloop.Ramble.watchkitapp` |
| SKU | dev.goodloop.ramble |
| Primary category | Productivity |
| Secondary category | Utilities |
| Age rating | 4+ |
| Copyright | 2026 Good Loop Software |
| Price | Free |
| In-app purchase | "Unlock Ramble", non-consumable, $14.99, product ID `dev.goodloop.ramble.unlock`. Family Sharing off |
| Subscription | `dev.goodloop.ramble.premium.monthly2` is removed from sale on release day (kept only as early-buyer proof on the server) |

## URLs

| Field | Value |
| --- | --- |
| Marketing URL | https://ramble.watch |
| Privacy Policy URL | https://ramble.watch/privacy |
| Terms of Use (EULA) | https://ramble.watch/terms |
| Support URL | https://ramble.watch/support (mailbox support@ramble.watch must receive mail before submission) |

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

Your best ideas show up on a walk, in the car, halfway through a run. Ramble keeps them without pulling you back to your phone. An idea, a to-do, a reminder. Messy is fine, and there's no reply to wait for. Your watch sends each thought over Wi-Fi, cellular, or your iPhone. No signal? It waits on your watch and goes out when you reconnect.

SETUP
In Settings, tap Your agent, then Connect your agent. Copy the message and paste it to your agent. That's it.

PRIVACY
- No accounts.
- Ramble's server is a relay, not an archive. Your audio is sent to a transcription provider and deleted as soon as the transcript is ready.
- Transcripts are deleted when your agent picks them up, or after 30 days.
- Your full history lives only on your iPhone.
- Disconnect any time.

TRANSCRIPTION
Ramble transcribes in the cloud, using providers that don't train on your audio. Set your language and add names to the vocabulary for better results.

WEBHOOKS
Ramble can also send each transcript to an HTTPS endpoint you choose.

PRICE
Free to download. 25 notes free, then $14.99 once. One-time purchase. No subscription. Fair use: 100 hours of audio per calendar month per purchase. Refunds are handled by Apple.

Requires an Apple Watch paired with an iPhone.
```

## Screenshot captions

Short, one thought each, in this order. Mindfulness first: a short headline and a smaller second line. The first screenshot shows the watch, not the phone.

1. Stay in the moment. (Talk to your watch. Your agent handles it later.)
2. Leave your phone behind. (Works without your iPhone. No signal? It sends when you reconnect.)
3. Get it out of your head. (Messy is fine.)
4. Connect your agent with one message. (No login. No OAuth. No accounts.)
5. Private by design. (Audio deleted once transcribed. Your history stays on your iPhone.)

## What's New

```
Ramble is now free to download. Your first 25 notes are free, then unlock once for $14.99. Every note is transcribed in the cloud, and your watch sends notes straight to Ramble, even without your iPhone nearby. If you bought Ramble before, every note transcribes with no unlock needed.
```

## App Privacy (privacy label)

Matches the privacy policy and `specs/delivery.md`. Ramble does no tracking and has no accounts. Proposed answers; **TODO: confirm in ASC** that each category maps as below.

| Data type (Apple's name) | Collected | Linked to the user | Purpose | Why |
| --- | --- | --- | --- | --- |
| User Content → Audio Data | Yes | No | App Functionality | Each recording is uploaded and sent to Ramble's transcription provider (Groq), then deleted once transcribed, at most 1 day after upload |
| User Content → Other User Content | Yes | No | App Functionality | Transcripts, held for the person's devices and agents, deleted on pickup or after 30 days (a point-in-time database backup keeps deleted rows up to 30 days for outage recovery) |
| Purchases → Purchase History | Yes | No | App Functionality | Apple's signed purchase record, to unlock notes |
| Usage Data or Diagnostics | TODO: decide | No | App Functionality | Per-note lengths, providers and outcomes, with no audio or text, used for usage monitoring and running the service |

Not collected: contact info, location, identifiers for tracking, browsing history. Webhook transcripts go from the iPhone straight to the person's own URL and never reach Ramble's server.

## App Review notes

```
Ramble gives every new install 25 free notes, then offers a one-time "Unlock Ramble" purchase. To test without an agent, record a note on the iPhone or watch: it transcribes and shows "Saved, no agent connected". Restore Purchases is in Settings.
```

TODO: confirm in ASC whether the reviewer needs a demo agent for "Connect your agent".
