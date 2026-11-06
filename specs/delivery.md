# Delivery

## Purpose
Who receives each transcript, when, and for how long: connecting an agent, what the agent receives and how it picks notes up, wake-up hooks, webhooks, what each delivery state means, how transcripts are kept and deleted, and the privacy wording that describes it. The exact HTTP contract, limits and status codes are in [relay-api.md](relay-api.md). How audio becomes a transcript is in [transcription.md](transcription.md). Where each string appears on the iPhone is in [phone.md](phone.md).

## Connecting an agent

### Requirement: A pairing code exists only while the Connect screen is open
The iPhone SHALL make a pairing code when its Connect screen opens, whether from onboarding, the Home "Connect" pill, or the "Connect your agent", "Connect again" and "Connect another" buttons. Opening the agent status screen SHALL NOT make a code. Only the iPhone can connect agents.

#### Scenario: Opening the agent screen with no agent
- GIVEN no agent is connected
- WHEN the person opens Settings → "Your agent"
- THEN they see "No agent yet", "Your notes are saved on your iPhone. Connect an agent to send the next ones." and a "Connect your agent" button
- AND no pairing code exists

### Requirement: One copy-paste message pairs the agent
The Connect screen SHALL show three steps, "Copy this message", "Paste it to your agent" and "Wait for it to connect", and a message copied with one tap: "I downloaded Ramble, connect it. My pairing code is <code>. Instructions: https://ramble.watch/docs".

#### Scenario: Copying and pasting
- GIVEN the Connect screen shows a live code
- WHEN the person taps "Copy", leaves Ramble, and comes back
- THEN the message was put on the clipboard with a success haptic, and the button reads "Copy again"
- AND step 3 reads "Waiting for your agent" with "Usually under a minute."

### Requirement: Codes work once and expire after 10 minutes
A pairing code SHALL connect one agent, expire 10 minutes after it is made, and be cancelled when another code is made. The screen counts down ("Works once · 5:30 left"). Codes are 12 characters shown as XXXX-XXXX-XXXX, accepted in any case with spaces and dashes ignored. The alphabet, attempt limits and agent cap are in [relay-api.md](relay-api.md).

#### Scenario: Expiry
- GIVEN a code was made 10 minutes ago and no agent used it
- WHEN the countdown reaches zero
- THEN the box reads "This code expired" and the Copy button becomes "New code"

### Requirement: Only the agent that pairs can recover its key
When an exchange is retried with the same request ID within the code's 10 minutes and before the agent's first inbox check, the relay SHALL return the same key. A retry with a different request ID SHALL be refused. Nobody can read a key back from the relay in any other way.

#### Scenario: Response lost
- GIVEN an agent's exchange succeeded but the response never reached it
- WHEN it repeats the exchange with the same code and request ID 30 seconds later
- THEN it receives the same key, and only one agent appears in the app

#### Scenario: Someone else replays the code
- GIVEN an agent paired 2 minutes ago and the code is visible in its chat
- WHEN another client sends that code with a different request ID
- THEN it gets no key, and the agent's key keeps working

### Requirement: The app shows the moment the agent connects
While the Connect screen is open and its code is live, the app SHALL check every 4 seconds for a connection. When one appears, step 3 SHALL read "Connected" with "Checked in just now", with a success haptic, and the primary button ("Continue" in onboarding, "Done" from Settings) becomes enabled. Until then it stays disabled, and "Set up later" or "Cancel" leaves without connecting.

#### Scenario: Agent connects while the person waits
- GIVEN the person pasted the message and returned to Ramble
- WHEN the agent exchanges the code
- THEN within about 4 seconds the screen shows "Connected" and the button is enabled

### Requirement: The agent cap is explained
When the person already has the most agents [relay-api.md](relay-api.md) allows, the Connect screen SHALL show "You've connected 10 agents. Disconnect one to connect another." instead of a code.

#### Scenario: Eleventh agent
- GIVEN 10 agents are connected
- WHEN the person taps "Connect another"
- THEN no code appears, and that message is shown

### Requirement: Agent keys are long-lived and scoped
Each agent key SHALL be 32 random bytes, work until the agent is disconnected, and read and acknowledge only that agent's own copies. A key cannot pair agents, upload notes, or read the copy for the person's own devices. The relay keeps only a hash of it.

#### Scenario: Another person's notes
- GIVEN two people each connected an agent
- WHEN one agent checks its inbox
- THEN it sees only the transcripts meant for it

### Requirement: Reinstalling starts over with agents
When the iPhone starts a fresh inbox (for example after a reinstall that lost its credentials), the person SHALL connect their agents again. Agents of the old inbox receive no further notes, and copies already waiting for them expire on the usual schedule.

#### Scenario: After a reinstall
- GIVEN an agent was connected and Ramble was reinstalled with a fresh inbox
- WHEN the person records a note
- THEN the old agent does not receive it, and the note reads "Saved, no agent connected"

## What the person sees per agent

### Requirement: The agent screen is built around one agent
The agent screen SHALL be titled "Your agent". Each connected agent gets a card with its name (what the agent called itself, 1 to 40 characters, set at pairing or later; "Agent" when it gave none or an invalid one, which never fails the pairing), a status of "Connected" (green) or "Hasn't checked in" (amber), and a last-used line such as "Checked in 2m ago · nothing waiting", "Last checked in 14h ago · 3 waiting" or "Hasn't checked in yet · nothing waiting". An agent "Hasn't checked in" when something waits for it and it has not checked its inbox for 12 hours, or never has.

#### Scenario: A quiet agent
- GIVEN 2 notes have waited for the agent and it last checked in 14 hours ago
- WHEN the person opens "Your agent"
- THEN the card is amber and reads "Hasn't checked in" and "Last checked in 14h ago · 2 waiting"
- AND it shows "If your agent lost its setup, connect it again with a fresh message." with a "Connect again" button

### Requirement: More than one agent stays quiet in the interface
The agent screen SHALL offer further agents only through the footnote "Using more than one agent? **Connect another**". "Connect another" and "Connect again" each pair a separate connection with its own key; an existing connection stays until the person disconnects it. With several agents connected, the title SHALL read "Your agents", each card has its own "Disconnect", and the bottom action reads "Disconnect all". The Settings row wording is in [phone.md](phone.md).

#### Scenario: Two agents
- GIVEN "Grok Bot" and "Muse" are connected
- WHEN the person opens the agent screen
- THEN it is titled "Your agents" and shows two cards, each with "Disconnect"

### Requirement: Disconnect cuts an agent off at once
Disconnecting an agent SHALL revoke its key immediately, delete every copy waiting for it, and remove its wake-up hook. Its next request gets a 401. Other agents stay connected.

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
When a transcript is ready, the relay SHALL make one copy for each agent that is connected at that moment and was paired before the note's recorded time. The recorded time comes from the recording device; times more than 5 minutes in the future are refused ([relay-api.md](relay-api.md)). Watch notes reach agents without the iPhone nearby.

#### Scenario: Agent paired after recording
- GIVEN a note was recorded at 9:00 and is still transcribing
- WHEN an agent pairs at 9:05 and the transcript is ready at 9:06
- THEN that agent receives no copy of the note

#### Scenario: A held note
- GIVEN a note recorded while an agent was connected is held for unlock ([subscription.md](subscription.md))
- WHEN the person unlocks and the note transcribes
- THEN the agent receives it as an item at that point

### Requirement: Silent notes go nowhere
A note with no speech detected ([transcription.md](transcription.md)) SHALL produce no agent copy, no wake-up ping and no webhook.

#### Scenario: Pocket recording
- GIVEN an agent and a webhook are set up
- WHEN a note transcribes as "No speech detected"
- THEN the agent, its hook and the webhook receive nothing

### Requirement: An item carries the transcript and when it was said
Each item an agent reads SHALL contain its item number (used to acknowledge it), the note ID, `created_at` (when recording started, with the recording device's UTC offset), `received_at` (when the relay accepted the note, UTC), `duration` (seconds, measured by the server) and `transcription` (the full text). It contains no audio, device ID or name.

#### Scenario: A note recorded offline
- GIVEN a note was recorded at 14:00 local time (UTC−5) and uploaded at 19:00 local time
- WHEN the agent reads it
- THEN `created_at` reads 2026-11-01T14:00:00-05:00 and `received_at` reads 2026-11-02T00:00:00Z

### Requirement: Agents pull, then acknowledge
An agent's inbox check SHALL return its waiting items oldest first, at most 50 at a time, and say whether more are waiting. Unacknowledged items SHALL come back on every check. Acknowledging deletes only that agent's copies, and acknowledging an item that is gone or not the agent's does nothing. Every call is safe to retry. Only a 401 means the agent was disconnected; a valid key on an endpoint it may not use gets a 403.

#### Scenario: Two agents, one acknowledges
- GIVEN "Grok Bot" and "Muse" each have a copy of a note
- WHEN Grok Bot acknowledges it
- THEN Muse's copy still comes back on Muse's next check

## Wake-up hooks

### Requirement: An agent can register its own wake-up hook
An agent MAY register one wake-up hook: a public HTTPS URL plus a few headers, within the rules in [relay-api.md](relay-api.md). The relay SHALL store the header values encrypted, refuse to store a hook when it cannot encrypt it, and never show the values again, to the agent or the app. The agent can replace or remove its hook at any time. Setting a hook SHALL send one ping at once with event "ramble.test" and the text "Ramble test ping: your wake-up hook works. Nothing new to pick up, no action needed.", and report that ping's HTTP status.

#### Scenario: Registering a hook
- GIVEN an agent has no hook
- WHEN it registers one with an Authorization header and a URL that answers 200
- THEN the URL receives the test ping, and the agent sees status 200
- AND reading its settings back shows the URL and the header name, but not the value

### Requirement: Hooks fire when a transcript is ready, without the transcript
When a copy is made for an agent with a hook, the relay SHALL POST to the hook, with the agent's headers, the body `{"event": "ramble.notes_waiting", "text": "New Ramble notes are waiting. Pull them from <relay>/inbox with your Ramble token, handle them, then ack.", "pull_url": "<relay>/inbox"}`. A ping SHALL never contain transcript text, note IDs or counts. Just before sending, the relay SHALL check again that the URL resolves to a public address, and skip the ping if it does not.

#### Scenario: A note arrives
- GIVEN an agent has a working hook
- WHEN a note's transcript is ready
- THEN the hook receives one "ramble.notes_waiting" ping, and the transcript is available only by checking the inbox

### Requirement: One ping per batch, best effort
After a ping, the relay SHALL send that agent no further ping until it checks its inbox or 10 minutes pass. Each ping is one attempt with a 5-second timeout, no retries, and no redirects followed. A failed ping never affects the note, which stays waiting.

#### Scenario: A burst of notes
- GIVEN an agent was pinged 2 minutes ago and has not checked in since
- WHEN three more transcripts are ready
- THEN no further ping is sent until it checks its inbox or 10 minutes have passed since the last ping

### Requirement: The app shows whether the hook works
An agent's card SHALL read "Wakes up when a note arrives" when its hook's last ping succeeded or no ping has been sent yet, and "Wake-up hook isn't answering" (amber) when the last ping got no 2xx response. The hook's URL and headers never reach the app.

#### Scenario: Hook fails
- GIVEN an agent's last ping timed out
- WHEN the person opens "Your agent"
- THEN its card reads "Wake-up hook isn't answering"

## Delivery states

### Requirement: Each note has one delivery state
Once a note's transcript exists, the iPhone SHALL give it one of these states, computed from what the relay reports for the note (copies made, waiting, picked up, removed unread, first pickup time) and from the webhook. A failed webhook outranks everything else, then any waiting copy. Earlier states (recording, uploading, transcribing, held) are in [phone.md](phone.md) and [watch.md](watch.md). The alert for copies still waiting after 12 hours is in [phone.md](phone.md).
- "Waiting for your agent": at least one agent copy is still waiting, even if other agents have picked theirs up.
- "Your agent has it": none is waiting and at least one was picked up. The note shows the first pickup time.
- "Not picked up": copies were made, and every one was removed unread (expired, deleted, or its agent was disconnected).
- "Saved, no agent connected": no copy was made because no eligible agent was connected.
- "Nothing to send · no speech detected": the note was silent.
- "Delivered to webhook": no agent copy, and the webhook accepted it.
- "Didn't send", with "Retry": the webhook gave up.

#### Scenario: Picked up
- GIVEN a note reads "Waiting for your agent"
- WHEN the agent acknowledges it at 9:15 and the iPhone next checks
- THEN the note reads "Your agent has it" and shows 9:15 as the pickup time

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
The person MAY set one webhook destination, edited under "Add destination" or "Edit destination". Webhooks and agents are independent and can be used together. The onboarding choice between them is in [phone.md](phone.md). "Remove destination" asks first: "Transcripts will no longer be sent anywhere." The editor SHALL accept only an HTTPS URL whose host is not localhost, a loopback, private or link-local IPv4 address, or an `.internal` host, and disable Save while the URL is invalid.

#### Scenario: Invalid URL
- GIVEN the editor is open
- WHEN the person types "http://example.com/hook"
- THEN it shows "URL must use HTTPS" and Save is disabled

### Requirement: The iPhone sends the webhook once it has the transcript
For every note with speech whose transcript reaches the iPhone while a destination is set, including watch notes, the iPhone SHALL POST one JSON body: `recording_id`, `created_at` (recording start, UTC), `duration` (seconds), `transcription`, and `device_id` (a random per-install ID, not tied to any account). The relay never sees the webhook URL or secret. "Send test webhook" SHALL POST the same shape with `"test": true`, a `recording_id` starting "test-", `duration` 0 and the text "This is a test webhook from Ramble.", then show "Test delivered" or "Failed — <reason>".

#### Scenario: Watch note to webhook
- GIVEN a webhook is set and the watch uploaded a note straight to the relay
- WHEN the iPhone next pulls that note's transcript
- THEN the iPhone POSTs it to the webhook

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
The destination SHALL show a green dot ("Last delivery succeeded") or a red dot ("Last delivery failed") from the most recent note whose webhook finished, and a grey dot ("Webhook not yet tested") before any has.

#### Scenario: Last one failed
- GIVEN the most recent finished webhook delivery failed
- WHEN the person opens Settings
- THEN the destination shows a red dot

## Retention and deletion

### Requirement: Agent copies are temporary
An agent's copy SHALL be deleted when that agent acknowledges it, when the agent is disconnected, when the person deletes waiting notes, or 30 days after the relay accepted the note, whichever comes first. An expired copy is never returned.

#### Scenario: Never picked up
- GIVEN an agent never checks in
- WHEN 30 days pass after a note was accepted
- THEN its copy is gone, and the note reads "Not picked up"

### Requirement: The copy for the person's own devices outlasts an absence
The transcript the person's own devices read SHALL be kept until the iPhone has acknowledged saving it and, for a watch note, the watch has read it, or until 30 days after it was ready, whichever comes first. It is separate from agent copies. The iPhone's local history is the only lasting copy ([phone.md](phone.md)).

#### Scenario: iPhone away for a week
- GIVEN the iPhone is off for 8 days while the watch uploads notes
- WHEN the iPhone comes back
- THEN it still pulls every transcript from those 8 days

#### Scenario: Watch has not read it yet
- GIVEN the iPhone acknowledged a watch note's transcript
- WHEN the watch app next opens
- THEN the watch can still read that transcript, after which it is deleted

### Requirement: Delete waiting notes
The agent screen SHALL offer "Delete waiting notes", which asks "Delete waiting notes?" with "Notes your agent hasn't picked up are deleted from the relay. Your agent stays connected, and the copies on this phone stay." It SHALL delete every agent copy still waiting and report "Deleted N waiting." or "Nothing was waiting." It SHALL NOT delete the copy for the person's own devices, notes still transcribing (they finish and make copies for agents connected then), connections, the free-note count or the unlock.

#### Scenario: Deleting
- GIVEN 4 copies are waiting across two agents and one note is still transcribing
- WHEN the person confirms "Delete waiting notes"
- THEN the 4 copies are deleted and the row reads "Deleted 4 waiting."
- AND both agents stay connected, and the transcribing note still reaches them when it is ready

### Requirement: Privacy wording matches what happens
The agent screen's "TEMPORARY BY DESIGN" note, the website privacy page, the llms files and the relay docs SHALL use: "Ramble's server is a relay, not an archive. Your audio is sent to a transcription provider and deleted as soon as the transcript is ready. Transcripts are deleted when your agent picks them up, or after 30 days. Your full history lives only on your iPhone." No copy SHALL say that audio never leaves the device. The privacy policy SHALL state that deleted transcripts can remain in the database's point-in-time backup for up to 30 days and are used only to recover from an outage. The App Store privacy label SHALL list Audio Data alongside the transcript data.

#### Scenario: Reading the privacy policy
- GIVEN a person opens https://ramble.watch/privacy
- WHEN they read how long transcripts are kept
- THEN the page names the 30-day relay limit and the up-to-30-day backup window
