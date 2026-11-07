# Delivery

## Purpose
Who receives each transcript, when, and for how long: connecting an agent, what the agent receives, wake-up hooks, webhooks, the delivery states and their words, how transcripts are kept and deleted, and the privacy wording. The HTTP contract, limits and status codes are in [relay-api.md](relay-api.md); how audio becomes a transcript is in [transcription.md](transcription.md); where each string sits on the iPhone is in [phone.md](phone.md).

## Connecting an agent

### Requirement: The Connect screen makes the pairing code
The iPhone SHALL make a pairing code only when its Connect screen opens, from onboarding, the Home "Connect" pill, or the "Connect your agent", "Connect again" and "Connect another" buttons. Opening the agent status screen SHALL NOT make a code. Only the iPhone can connect agents.

#### Scenario: Opening the agent screen with no agent
- GIVEN no agent is connected
- WHEN the person opens Settings → "Your agent"
- THEN they see "No agent yet", "Notes stay on your iPhone until you connect one. It sets itself up from one message.", "Works with Muse, Grok Bot, ChatGPT and more" and a "Connect your agent" button, and no pairing code exists

### Requirement: One copy-paste message pairs the agent
The Connect screen SHALL show three steps, "Copy this message", "Paste it to your agent" and "Wait for it to connect", and a message copied with one tap: "I downloaded Ramble, connect it. My pairing code is <code>. Instructions: https://ramble.watch/docs".

#### Scenario: Copying and pasting
- GIVEN the Connect screen shows a live code
- WHEN the person taps "Copy", leaves Ramble, and comes back
- THEN the message was put on the clipboard with a success haptic, and the button reads "Copy again"
- AND step 3 reads "Waiting for your agent" with "Usually under a minute."

### Requirement: Codes work once and expire after 10 minutes
A pairing code SHALL connect one agent and stay valid for 10 minutes after it is made, even if the Connect screen closes. The screen counts down ("Works once · 5:30 left"). Code length and format are in [relay-api.md](relay-api.md).

#### Scenario: Expiry
- GIVEN a code was made 10 minutes ago and no agent used it
- WHEN the countdown reaches zero
- THEN the box reads "This code expired" and the Copy button becomes "New code"

### Requirement: A key is handed out once
The relay SHALL return an agent's key only in the answer to the exchange that used the code. Nobody, including the agent that paired, can read a key back from the relay later.

#### Scenario: Response lost
- GIVEN an agent's exchange succeeded but the response never reached it
- WHEN it repeats the exchange with the same code 30 seconds later
- THEN it gets no key, the app shows the unused agent as "Hasn't checked in yet", and the person connects again with a new code

#### Scenario: Someone else replays the code
- GIVEN an agent paired 2 minutes ago and the code is visible in its chat
- WHEN another client sends that code
- THEN it gets no key, and the agent's key keeps working

### Requirement: The app shows the moment the agent connects
While the Connect screen is open and its code is live, the app SHALL check every 4 seconds for a connection. When one appears, step 3 SHALL read "Connected" with "Checked in just now", with a success haptic, and the primary button ("Continue" in onboarding, "Done" from Settings) becomes enabled. Until then it stays disabled, and "Set up later" or "Cancel" leaves without connecting.

#### Scenario: Agent connects while the person waits
- GIVEN the person pasted the message and returned to Ramble
- WHEN the agent exchanges the code
- THEN within about 4 seconds the screen shows "Connected" and the button is enabled

### Requirement: Agent keys are long-lived and scoped
Each agent key SHALL be 32 random bytes, work until the agent is disconnected, and read and acknowledge only that agent's own copies. A key cannot pair agents, upload notes, or read the copy for the person's own devices. The relay keeps only a hash of it.

#### Scenario: Another person's notes
- GIVEN two people each connected an agent
- WHEN one agent checks its inbox
- THEN it sees only the transcripts meant for it

### Requirement: Reinstalling keeps or replaces the agents with the inbox
When Ramble is reinstalled and the iPhone still holds its inbox credential, it SHALL keep the same inbox, with its agents, free-note count and unlock. When the credential is gone, the iPhone starts a fresh inbox and the person SHALL connect their agents again. Agents of the old inbox receive only notes the old inbox had already accepted; their waiting copies expire on the usual schedule. Notes that upload under the fresh inbox go only to agents connected when the server accepted each note. Restoring the purchase is covered in [purchase.md](purchase.md).

#### Scenario: Fresh inbox
- GIVEN an agent was connected and the iPhone starts a fresh inbox
- WHEN the person records a note before connecting any agent
- THEN the old agent does not receive it, and the note reads "Saved, no agent connected"

## What the person sees per agent

### Requirement: Agent cards show status and last check-in
The agent screen SHALL be titled "Your agent" and give each agent a card: its name if it gave one ([relay-api.md](relay-api.md)), "Connected" (green) or "Hasn't checked in" (amber), and a line such as "Checked in 2m ago · nothing waiting", "Hasn't checked in yet · nothing waiting", or "Last checked in 14h ago · 2 waiting" when something is waiting. It is "Hasn't checked in" when a copy waits for it and it has not checked its inbox in 12 hours, or ever. Dialogs call an unnamed agent "Agent".

#### Scenario: A quiet agent
- GIVEN 2 notes have waited for the agent and it last checked in 14 hours ago
- WHEN the person opens "Your agent"
- THEN the card is amber and reads "Hasn't checked in" and "Last checked in 14h ago · 2 waiting"
- AND it shows "If your agent lost its setup, connect it again with a fresh message." with a "Connect again" button

### Requirement: More than one agent stays quiet in the interface
The agent screen SHALL offer further agents only through the footnote "Using more than one agent? **Connect another**". "Connect another" and "Connect again" each pair a separate connection; an existing one stays until disconnected. With more than one agent, the title SHALL read "Your agents", each card gets a "Disconnect", and the bottom action reads "Disconnect all".

#### Scenario: Two agents
- GIVEN "Grok Bot" and "Muse" are connected
- WHEN the person opens the agent screen
- THEN it is titled "Your agents" and shows two cards, each with "Disconnect"

### Requirement: Disconnect cuts an agent off at once
Disconnecting an agent SHALL revoke its key immediately, delete every copy waiting for it, and remove its wake-up hook. Other agents stay connected.

#### Scenario: Disconnect one of two
- GIVEN "Grok Bot" has 3 notes waiting and "Muse" has 1
- WHEN the person disconnects "Grok Bot"
- THEN Grok Bot's 3 copies are deleted and its key stops working
- AND Muse's copy is untouched

### Requirement: Disconnect asks first
The app SHALL confirm before disconnecting: "Disconnect your agent?" with "It loses access immediately, and anything waiting for it is deleted." for a single agent; "Disconnect <name>?" with "It loses access immediately, and anything waiting for it is deleted. Your other agents stay connected." for one of several; "Disconnect your agents?" with "They lose access immediately, and anything waiting for them is deleted." for "Disconnect all".

#### Scenario: Disconnect all
- GIVEN two agents are connected
- WHEN the person taps "Disconnect all"
- THEN "Disconnect your agents?" appears, and nothing changes until they confirm

## What each agent receives

### Requirement: Each eligible agent gets its own copy
When a transcript is ready, the relay SHALL make one copy for each agent that is connected at that moment and was already connected when the server accepted the note's audio. The recording device's clock plays no part. A note whose transcript comes from a hand retry ([transcription.md](transcription.md)) SHALL follow the same rule, with the moment the server accepted the retry: its copies, hook pings and webhook follow at the moment the retry succeeds. Watch notes reach agents without the iPhone nearby.

#### Scenario: Agent paired after upload
- GIVEN a note reached the server at 9:00 and is still transcribing
- WHEN an agent pairs at 9:05 and the transcript is ready at 9:06
- THEN that agent receives no copy of the note

#### Scenario: Recorded offline, uploaded after pairing
- GIVEN a note was recorded on the watch at 8:00 with no connection
- WHEN an agent pairs at 9:00 and the note reaches the server at 9:30
- THEN that agent receives a copy

#### Scenario: Retry succeeds
- GIVEN a note that reached the server at 9:00 failed, agent A was paired at 8:00 and agent B at 12:00
- WHEN the person retries it at 11:00 and the transcript is ready
- THEN only agent A gets a copy, its hook is pinged, and the iPhone sends the webhook

### Requirement: Silent notes go nowhere
A note with no speech detected ([transcription.md](transcription.md)) SHALL produce no agent copy, no wake-up ping and no webhook.

#### Scenario: Pocket recording
- GIVEN an agent and a webhook are set up
- WHEN a note transcribes with no speech detected
- THEN the agent, its hook and the webhook receive nothing

### Requirement: An item carries the transcript and when it was said
Each item an agent reads SHALL give the note ID, when recording started (with the recording device's UTC offset), when the relay accepted it (UTC), the length measured by the server, and the full transcript, plus an item number to acknowledge it by. It carries no audio, device ID or name. Field names: [relay-api.md](relay-api.md).

#### Scenario: A note recorded offline
- GIVEN a note was recorded at 14:00 local time (UTC−5) and uploaded at 19:00 local time
- WHEN the agent reads it
- THEN `created_at` reads 2026-11-01T14:00:00-05:00 and `received_at` reads 2026-11-02T00:00:00.000Z

### Requirement: Agents pull, then acknowledge
An agent's inbox check SHALL return its waiting items oldest first, at most 50 at a time, and say whether more are waiting. Unacknowledged items SHALL come back on every check. Acknowledging deletes only that agent's copies.

#### Scenario: Two agents, one acknowledges
- GIVEN "Grok Bot" and "Muse" each have a copy of a note
- WHEN Grok Bot acknowledges it
- THEN Muse's copy still comes back on Muse's next check

## Wake-up hooks

### Requirement: An agent can register its own wake-up hook
An agent MAY register, replace or remove one wake-up hook: a public HTTPS URL with up to 8 headers ([relay-api.md](relay-api.md)). Setting a hook SHALL send one test ping at once, with the text "Ramble test ping: your wake-up hook works. Nothing new to pick up, no action needed.", and report its HTTP status to the agent. The relay SHALL store header values only encrypted, refuse a hook it cannot encrypt, and never show the values again, to the agent or the app.

#### Scenario: Registering a hook
- GIVEN an agent has no hook
- WHEN it registers one with an Authorization header and a URL that answers 200
- THEN the URL receives the test ping, and the agent sees status 200
- AND reading the hook back shows the header name but not its value

### Requirement: Hooks fire when a transcript is ready, without the transcript
When a copy is made for an agent with a hook, the relay SHALL ping the hook to say notes are waiting. A ping SHALL never contain transcript text, note IDs or counts; the agent reads its notes by checking its inbox. After a ping, no other ping goes to that agent until it checks its inbox or 10 minutes pass. A ping is one try; a failed ping never affects the note. Body, timeout and address checks: [relay-api.md](relay-api.md).

#### Scenario: A burst of notes
- GIVEN an agent with a working hook has not checked in since a ping 2 minutes ago
- WHEN three more transcripts are ready
- THEN no ping goes out until it checks its inbox or 10 minutes have passed since the last one

### Requirement: The app shows whether the hook works
An agent's card SHALL read "Wakes up when a note arrives" when its hook's last ping succeeded or no ping has gone out yet, and "Wake-up hook isn't answering" (amber) when the last ping got no 2xx response. The hook's URL and headers never reach the app.

#### Scenario: Hook fails
- GIVEN an agent's last ping timed out
- WHEN the person opens "Your agent"
- THEN its card reads "Wake-up hook isn't answering"

## Delivery states

### Requirement: Each note has one delivery state
Once a note's transcript exists, the iPhone SHALL give it exactly one of the states below, using these words on every screen. It computes them from what the relay reports per note (copies made, waiting, picked up, removed unread, first pickup time) and from the webhook. A silent note is always "Nothing to send · no speech detected"; otherwise a failed webhook comes first, then any waiting copy. Earlier states (uploading, transcribing, held) are in [phone.md](phone.md) and [watch.md](watch.md).

| Shown | When |
|---|---|
| "Waiting for your agent" | at least one agent copy is still waiting, even if another agent picked up its own |
| "Your agent has it" | none is waiting and at least one was picked up; shows the first pickup time |
| "Not picked up" | copies were made and every one was removed unread (expired, deleted, or its agent disconnected) |
| "Saved, no agent connected" | no copy was made because no eligible agent was connected |
| "Nothing to send · no speech detected" | the note was silent |
| "Delivered to webhook" | no agent copy, and the webhook accepted it |
| "Didn't send", with "Retry" | the webhook gave up |

#### Scenario: Picked up
- GIVEN a note reads "Waiting for your agent"
- WHEN the agent acknowledges it at 9:15 and the iPhone next checks
- THEN the note reads "Your agent has it" and shows 9:15

#### Scenario: Agent disconnected before reading
- GIVEN a note's only copy is waiting
- WHEN the person disconnects that agent and the iPhone next checks
- THEN the note reads "Not picked up"

#### Scenario: Connecting later doesn't change old notes
- GIVEN a note reads "Saved, no agent connected"
- WHEN the person connects an agent
- THEN the note keeps that state, and no agent receives it

## Webhooks

### Requirement: One optional webhook destination
The person MAY set one webhook destination, under "Add destination" or "Edit destination". Webhooks and agents are independent and can be used together. "Remove destination" asks first: "Transcripts will no longer be sent anywhere." The editor SHALL accept only an HTTPS URL whose host is not localhost, a loopback, private or link-local IPv4 address, or an `.internal` host, and disable Save while the URL is invalid.

#### Scenario: Invalid URL
- GIVEN the editor is open
- WHEN the person types "http://example.com/hook"
- THEN it shows "URL must use HTTPS" and Save is disabled

### Requirement: The iPhone sends the webhook once it has the transcript
For every note with speech whose transcript reaches the iPhone while a destination is set, including watch notes, the iPhone SHALL POST one JSON body: `recording_id`, `created_at` (recording start, in UTC, unlike the agent item), `duration` (seconds), `transcription`, and `device_id` (a random per-install ID, not tied to any account). The relay never sees the webhook URL or secret.

#### Scenario: Watch note to webhook
- GIVEN a webhook is set and the watch uploaded a note straight to the relay
- WHEN the iPhone next pulls that note's transcript
- THEN the iPhone POSTs it to the webhook

### Requirement: Test webhooks are marked
"Send test webhook" SHALL POST the same shape with `"test": true`, a `recording_id` starting "test-", `duration` 0 and the text "This is a test webhook from Ramble.", then show "Test delivered" or "Failed — <reason>".

#### Scenario: Test succeeds
- GIVEN the endpoint returns 200
- WHEN the person taps "Send test webhook"
- THEN the editor shows "Test delivered"

### Requirement: Webhook requests are signed
Each webhook request SHALL carry `X-Webhook-Signature: sha256=<hex>`, the HMAC-SHA256 of the exact body keyed with the signing secret. The secret is 24 random bytes made by the app, hidden until revealed, copyable, and replaceable with "Regenerate" after "Your endpoint will need the new secret to accept requests."

#### Scenario: Verifying
- GIVEN an endpoint holds the signing secret
- WHEN it computes HMAC-SHA256 over the raw body
- THEN the result matches the header after "sha256="

### Requirement: Webhook retries are short, then the person decides
A delivery SHALL succeed on any 2xx response within 10 seconds. Otherwise the iPhone SHALL try 3 times in total, waiting 30 seconds and then 2 minutes, then mark the note "Didn't send". "Retry" starts 3 fresh attempts. Pending webhooks survive the app closing and wait while the iPhone is locked.

#### Scenario: Endpoint down
- GIVEN the endpoint returns 500
- WHEN a note's transcript arrives
- THEN after the third failed attempt the note reads "Didn't send", and its activity shows "Webhook failed after 3 attempts — HTTP 500"

### Requirement: Webhook health is shown
The destination SHALL show a green dot when the most recent finished webhook was delivered, a red dot when it failed, and a grey dot before any has finished. VoiceOver reads "Last delivery succeeded", "Last delivery failed" or "Webhook not yet tested".

#### Scenario: Last one failed
- GIVEN the most recent finished webhook delivery failed
- WHEN the person opens Settings
- THEN the destination shows a red dot

## Retention and deletion

### Requirement: Agent copies are temporary
An agent's copy SHALL be deleted when that agent acknowledges it, when the agent is disconnected, when the person deletes waiting notes, or 30 days after the copy was made (when the transcript was ready), whichever comes first. An expired copy is never returned.

#### Scenario: Never picked up
- GIVEN an agent never checks in
- WHEN 30 days pass after a note's transcript was ready
- THEN its copy is gone, and the note reads "Not picked up"

### Requirement: The copy for the person's own devices outlasts an absence
The transcript the person's own devices read SHALL be kept until the iPhone has acknowledged saving it and, for a watch note, the watch has read it, or until 30 days after it was ready, whichever comes first. The iPhone's local history is the only lasting copy ([phone.md](phone.md)).

#### Scenario: iPhone away for a week
- GIVEN the iPhone is off for 8 days while the watch uploads notes
- WHEN the iPhone comes back
- THEN it still pulls every transcript from those 8 days

#### Scenario: Watch has not read it yet
- GIVEN the iPhone acknowledged a watch note's transcript
- WHEN the watch app next opens
- THEN the watch can still read that transcript, after which it is deleted

### Requirement: Delete waiting notes
The agent screen SHALL offer "Delete waiting notes", which asks "Delete waiting notes?" with "Notes your agent hasn't picked up are deleted from the relay. Notes still being transcribed will still be sent. Your agent stays connected, and the copies on this phone stay." It SHALL delete every agent copy still waiting, then read "Deleted N waiting." or "Nothing was waiting."

#### Scenario: Deleting
- GIVEN 4 copies are waiting across two agents
- WHEN the person confirms "Delete waiting notes"
- THEN the 4 copies are deleted and the row reads "Deleted 4 waiting."

### Requirement: What deleting waiting notes keeps
Deleting waiting notes SHALL NOT delete the copy for the person's own devices, notes still transcribing (they finish and make copies for the agents connected then), connections, the free-note count or the unlock.

#### Scenario: A note still transcribing
- GIVEN a note is transcribing and an agent is connected
- WHEN the person deletes waiting notes
- THEN the note still reaches the agent when its transcript is ready

### Requirement: One privacy wording everywhere
The agent screen's "TEMPORARY BY DESIGN" note, the website privacy page, the llms files and the relay docs SHALL use: "Ramble's server is a relay, not an archive. Your audio is sent to a transcription provider and deleted as soon as the transcript is ready. Transcripts are deleted when your agent picks them up, or after 30 days. Your full history lives only on your iPhone." No copy SHALL say that audio never leaves the device.

#### Scenario: Reading the agent screen
- GIVEN an agent is connected
- WHEN the person opens "Your agent"
- THEN the privacy note uses that wording

### Requirement: Backups and the App Store label are disclosed
The privacy policy SHALL name the one transcription provider Ramble sends audio to (Groq, [transcription.md](transcription.md)), say that transcripts go to the agents and webhook the person connects, and state that deleted transcripts can remain in the database's point-in-time backup for up to 30 days and are used only to recover from an outage. It is what the onboarding consent line links to ([phone.md](phone.md)). The App Store privacy label SHALL list Audio Data alongside the transcript data.

#### Scenario: Reading the privacy policy
- GIVEN a person opens https://ramble.watch/privacy
- WHEN they read how long transcripts are kept
- THEN the page names the 30-day relay limit and the up-to-30-day backup window
- AND it names Groq as the transcription provider
