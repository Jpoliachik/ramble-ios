# Connecting Muse to Ramble

Instructions for Muse, written so you can paste them in directly. Replace `RELAY_URL` with your relay's base URL, either the hosted one once it exists or your own deployment.

Muse has no inbound push API. It connects with a pairing code and then checks for new thoughts on a schedule.

---

**Paste into Muse:**

> I use Ramble to record thoughts on my Apple Watch. Ramble transcribes them and holds them in a relay at `RELAY_URL` until you pick them up. Please set this up:
>
> 1. **Pair.** When I give you a Ramble pairing code (it looks like `K7QX-MP4D`), send `POST RELAY_URL/pair/exchange` with the JSON body `{"code": "<the code>"}`. The response includes a `token`. Save it as a secret named `RAMBLE_TOKEN`. Don't repeat it back to me in chat. The code works once and expires after 10 minutes, so if it fails, ask me for a new one.
>
> 2. **Check every 15 minutes** with a scheduled job:
>    - `GET RELAY_URL/inbox` with the header `Authorization: Bearer <RAMBLE_TOKEN>`.
>    - The response has `items`, oldest first. Each one has `id`, `recording_id`, `created_at`, `duration` (seconds), and `transcription`.
>    - Handle each `transcription` as if I had sent it to you directly. If it's a task, do it or track it. If it's a note, file it where I keep notes. If you aren't sure, save it and mention it the next time we talk.
>    - After you've handled an item, send `POST RELAY_URL/inbox/ack` with `{"ids": [<id>, ...]}` and the same header. This deletes it from the relay.
>    - If `has_more` is true, pull again with `?since=<next_since>`.
>
> 3. **If a check returns 401**, I disconnected you in Ramble. Stop the scheduled job and let me know.
>
> I don't need a reply for each thought. I'll check results later.

---

## What to expect

- New thoughts arrive within one check interval, about 15 minutes at the suggested cadence. Muse never gets them in real time, and a live conversation won't be interrupted.
- Anything Muse doesn't pick up within 24 hours is deleted from the relay. It stays in Ramble on your phone.
- To disconnect, open Ramble, go to Settings → Send to your agent → Muse, and tap Disconnect. Muse's token stops working immediately.

## Checking it worked

1. Record a short thought on the Watch, something like "Test. Remind me to water the plants."
2. On the phone, the recording should show it's waiting for an agent. In Settings, Muse shows one pending.
3. After Muse's next check, the pending count drops to 0 and Muse acts on the thought. That means the relay has deleted it.
