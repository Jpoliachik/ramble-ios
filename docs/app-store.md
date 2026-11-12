# Ramble — App Store metadata

This file is the source of truth for the App Store listing. Change the copy here first, then push it to App Store Connect. Muse can do that with the App Store Connect API. Character counts are in brackets after each heading.

Fields marked **TODO: confirm in ASC** haven't been checked against App Store Connect yet. Fill them in from the live listing the next time someone pulls it.

Pricing words follow `specs/purchase.md` ("What Ramble says about price"): the price story is "Free to try. 25 notes free, then $14.99 once." Never "trial", "premium", "Subscribe", or a price per month. Privacy words follow `specs/delivery.md` ("One privacy wording everywhere"). No on-device transcription claims, and no open-source claims.

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
Send thoughts to your AI agent
```

This field ranks in search, so it carries the words people type (thoughts, AI, agent). The mood ("Say it. Let it go.") lives in the screenshots and promo text.

## Keywords [100 / 100]

Commas with no spaces. Don't repeat words that are already in the name or subtitle, because Apple indexes those fields anyway. Don't use competitor or agent brand names, because Apple rejects them. "offline" is fair because recording works offline; never imply offline transcription.

```
assistant,memo,dictation,transcribe,speech,mindful,wrist,todo,reminder,idea,walk,run,offline,capture
```

## Promotional text [148 / 170]

You can change this field without a new app version.

```
Say the thought to your Apple Watch and let it go. No reply to wait for, no signal needed. Your agent picks it up later, and you stay where you are.
```

## Description

```
Say it. Let it go. Ramble is the one-way line from your Apple Watch to your agent.

A thought comes on a run, at the park, in the middle of dinner. Tap your watch, say it, and put your arm down. Nothing comes back: no reply, no follow-up, no pull into solving it right now. Your agent picks it up later and takes care of it. You only check in if it needs you.

No signal? It waits on your watch and sends when you're back online, over Wi-Fi, cellular, or your iPhone. An idea, a to-do, a reminder. Messy is fine.

SETUP
In Settings, tap Your agent, then Connect your agent. Copy the message and paste it to your agent. That's it.

PRIVACY
- No accounts.
- Ramble's server is a relay, not an archive. Your audio is sent to a transcription provider and deleted as soon as the transcript is ready.
- Transcripts are deleted when your agent picks them up, or after 30 days.
- Your full history lives only on your iPhone.
- Basic usage stats for each note, like its length, under a random ID. Never your audio or your words.
- Disconnect any time.

TRANSCRIPTION
Ramble transcribes in the cloud, using a provider that doesn't train on your audio. Set your language and add names to the vocabulary for better results.

WEBHOOKS
Ramble can also send each transcript to an HTTPS endpoint you choose.

PRICE
Free to try. 25 notes free, then $14.99 once. One-time purchase. No subscription. Refunds are handled by Apple.

Requires an Apple Watch paired with an iPhone.
```

## Screenshot captions

Short, one thought each, in this order. Mindfulness first: a short headline and a smaller second line. The first screenshot shows the watch, not the phone.

The iPhone screenshots (1206 × 2622, the size App Store Connect accepted) and the product page header (5244 × 2950 and 3840 × 1646) are in `images/appstore/2026-sunset/`. Their HTML source is in `source/` there (open `one-line.html?bg=w` for the shipped look: the light sunset wash of the web hero and one flowing line; it renders at 1290 × 2796, so scale to 1206 × 2622); change the copy here first, then re-render. iPad gets one plain 13-inch screenshot (2064 × 2752), `ipad/ipad-1.png`: Home on an iPad on the sunset background, with no headline. The watch can't pair with an iPad, so the iPad listing doesn't pitch anything. Render it with `node source/ipad-render.js <abs path to one-line.html> <out png>`. Apple Watch screenshots (422 × 514, Ultra simulator) are in `watch/`, and the unlock sheet screenshot for the in-app purchase review is in `review/`.

1. Stay in the moment. (Say it. Let it go. Nothing comes back to your wrist.)
2. Leave your phone behind. (No signal needed. It sends later.)
3. Get it out of your head. (Messy is fine.)
4. Connect your agent with one message. (No login. No accounts.)
5. Private by design. (Deleted after delivery. History stays only on your phone.)

## What's New (1.2.0)

```
Ramble is now free to download. Your first 25 notes are free, then unlock once for $14.99. Every note is transcribed in the cloud, and your watch sends notes straight to Ramble, even without your iPhone nearby. If you bought Ramble before, there's nothing to unlock.
```

## App Privacy (privacy label)

Matches the privacy policy, `specs/delivery.md` and each app's `PrivacyInfo.xcprivacy`. Ramble does no tracking and has no accounts. These are the answers set in App Store Connect.

| Data type (Apple's name) | Collected | Linked to the user | Purpose | Why |
| --- | --- | --- | --- | --- |
| User Content → Audio Data | Yes | No | App Functionality | Each recording is uploaded and sent to Ramble's transcription provider (Groq), then deleted once transcribed, at most 1 day after upload |
| User Content → Other User Content | Yes | No | App Functionality | Transcripts, held for the person's devices and agents, deleted on pickup or after 30 days (a point-in-time database backup keeps deleted rows up to 30 days for outage recovery) |
| Purchases → Purchase History | Yes | No | App Functionality | Apple's signed purchase record, to unlock notes |
| Identifiers → Device ID | Yes | No | App Functionality | A random per-install ID (not the IDFA or IDFV) the iPhone sends while setting up App Attest, held with the one-time challenge until it expires |
| Usage Data → Product Interaction | Yes | No | Analytics, App Functionality | One row per note under a random usage ID (device, times, length, result, tries, settings on or off, app version), never audio or text, kept to fix problems and see how Ramble is used (`specs/usage.md`) |

Not collected: contact info, location, identifiers for tracking, browsing history. Webhook transcripts go from the iPhone straight to the person's own URL and never reach Ramble's server.

## App Review notes

```
Ramble gives every new install 25 free notes, then offers a one-time "Unlock Ramble" purchase. To test without an agent, record a note on the iPhone or watch: it transcribes and shows "Saved, no agent connected". Restore Purchases is in Settings.
```

TODO: confirm in ASC whether the reviewer needs a demo agent for "Connect your agent".
