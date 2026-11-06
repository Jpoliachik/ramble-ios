# Delivery

## Purpose
Who receives each transcript, when, and for how long: connecting an agent, what the agent receives and how it picks notes up, wake-up hooks, webhooks, the delivery status the person sees on the iPhone, and how transcripts are kept and deleted. The exact HTTP contract is in [relay-api.md](relay-api.md); how audio becomes a transcript is in [transcription.md](transcription.md).

## Connecting an agent

### Requirement: Connecting is an explicit tap that makes a code
The iPhone app SHALL make a pairing code only when the person taps "Connect your agent", "Connect again" or "Connect another", never just by opening the agent screen. Connecting an agent is possible only from the iPhone.

#### Scenario: Opening the agent screen
- GIVEN no agent is connected
- WHEN the person opens Settings → "Your agent"
- THEN they see "No agent yet", "Notes stay on your iPhone until you connect one. It sets itself up from one message." and a "Connect your agent" button
- AND no pairing code exists yet

### Requirement: One copy-paste message pairs the agent
The Connect screen SHALL show three steps, "Copy this message", "Paste it to your agent" and "Wait for it to connect", and a message the person copies with one tap: "I downloaded Ramble, connect it. My pairing code is <code>. Instructions: https://ramble.watch/docs".

#### Scenario: Copying and pasting
- GIVEN the Connect screen shows a live code
- WHEN the person taps "Copy"
- THEN the message is on the clipboard, the phone gives a success haptic, and the button reads "Copied", then "Copy again"
- AND when they leave the app and come back, step 3 reads "Waiting for your agent" with "Usually under a minute."

### Requirement: Pairing codes are short-lived, single-use and hard to guess
A pairing code SHALL be 12 characters from an alphabet without look-alike characters (no 0, O, 1, I, L or U), shown as three groups of four, work for one agent only, and expire 10 minutes after it is made. Making a new code SHALL cancel the previous one. Codes are accepted in any case, with spaces and dashes ignored. Attempts to exchange codes are rate-limited (limits in [relay-api.md](relay-api.md)).

#### Scenario: Countdown and expiry
- GIVEN a code was made 4 minutes and 30 seconds ago
- THEN the message box reads "Works once · 5:30 left"
- WHEN the 10 minutes run out
- THEN it reads "This code expired" and the Copy button becomes "New code"

#### Scenario: A used code
- GIVEN an agent exchanged a code and has since checked its inbox
- WHEN anyone sends the same code again
- THEN the relay refuses it as invalid or expired, and no second agent is connected

### Requirement: A retried exchange gets the same key
When an agent sends the same code again before its first inbox check and within the code's 10 minutes, the relay SHALL return the same agent key instead of failing, so a lost response never costs the person a new code.

#### Scenario: Response lost
- GIVEN an agent's exchange succeeded but the response never reached it
- WHEN it sends the same code again 30 seconds later
- THEN it receives the same key, and only one agent appears in the app

### Requirement: The app shows the moment the agent connects
While the Connect screen is open and its code is live, the app SHALL check every 4 seconds for a new connection. When one appears, step 3 SHALL read "Connected" with "Checked in just now", the phone gives a success haptic, and the primary button ("Continue" in onboarding, "Done" from Settings) becomes enabled. The button stays disabled until then; "Set up later" or "Cancel" leaves without connecting.

#### Scenario: Agent connects while the person waits
- GIVEN the person pasted the message and returned to Ramble
- WHEN the agent exchanges the code
- THEN within about 4 seconds the screen shows "Connected" and the button becomes enabled

### Requirement: Agents may name themselves
An agent MAY send a name of 1 to 40 characters when it pairs, and change it later. The relay SHALL trim it to one line; a missing or invalid name at pairing SHALL leave the agent unnamed rather than fail the pairing. The app shows an unnamed agent as "Agent".

#### Scenario: Named at pairing
- GIVEN an agent pairs with the name "Grok Bot"
- WHEN the person opens "Your agent"
- THEN the agent's card is labelled "Grok Bot"

### Requirement: Agent keys are long-lived, hashed and scoped
Each agent key SHALL be 32 random bytes, work until the agent is disconnected, and read and acknowledge only that agent's own copies. The relay SHALL store only a hash of the key, except that a newly issued key is kept beside its pairing code until the agent's first inbox check or the code's 10 minutes end, whichever comes first. A key cannot pair agents, upload notes or read the phone's or watch's copies.

#### Scenario: A key from another inbox
- GIVEN two people each connected an agent
- WHEN one agent checks its inbox
- THEN it sees only the transcripts meant for it

## What the person sees per agent

### Requirement: The agent screen is built for one agent
The agent screen SHALL be titled "Your agent" and present one agent. Each connected agent SHALL get a card showing its name, a status of "Connected" (green) or "Hasn't checked in" (amber), and a line saying when it last checked in and how much is waiting, like "Checked in 2m ago · nothing waiting" or "Last checked in 14h ago · 3 waiting". An agent is "Hasn't checked in" when something is waiting for it and it has not checked in for 12 hours (or never).

#### Scenario: A quiet agent
- GIVEN 2 notes have waited for the agent and it last checked in 14 hours ago
- WHEN the person opens "Your agent"
- THEN the card is amber, reads "Hasn't checked in" and "Last checked in 14h ago · 2 waiting"
- AND it shows "If your agent lost its setup, connect it again with a fresh message." with a "Connect again" button

#### Scenario: Never checked in
- GIVEN an agent paired but has never checked its inbox
- THEN its card reads "Hasn't checked in yet · nothing waiting"

### Requirement: More than one agent is supported but kept quiet
The app SHALL let the person connect further agents from a footnote, "Using more than one agent? **Connect another**". With more than one agent connected, the title SHALL read "Your agents", each card SHALL have its own "Disconnect", and the bottom action SHALL read "Disconnect all". The Settings row reads "N agents connected", or "<name> hasn't checked in" when one has gone quiet.

#### Scenario: Two agents
- GIVEN "Grok Bot" and "Muse" are connected
- WHEN the person opens Settings
- THEN the row reads "Your agents" and "2 agents connected"

### Requirement: Disconnect cuts an agent off at once
Disconnecting an agent SHALL revoke its key immediately, delete every copy waiting for it, and remove its wake-up hook. Its next request gets a 401. Other agents stay connected. The person confirms first: "Disconnect your agent?" with "It loses access immediately, and anything waiting for it is deleted." (one agent), "Disconnect <name>?" with "…Your other agents stay connected." (one of several), or "Disconnect your agents?" with "They lose access immediately, and anything waiting for them is deleted." (Disconnect all).

#### Scenario: Disconnect one of two
- GIVEN "Grok Bot" has 3 notes waiting and "Muse" has 1
- WHEN the person disconnects "Grok Bot"
- THEN Grok Bot's 3 copies are deleted and its key stops working
- AND Muse's copy is untouched

### Requirement: Connecting again adds a connection
"Connect again" and "Connect another" SHALL each pair a new agent connection with a new key. An existing connection stays until the person disconnects it.

#### Scenario: Reconnecting a quiet agent
- GIVEN one quiet agent is connected
- WHEN the person taps "Connect again" and the agent pairs with the new code
- THEN two cards are shown until the person disconnects the old one

## What each agent receives

### Requirement: Each connected agent gets its own copy of every new transcript
When a transcript is ready, the relay SHALL make one copy for each agent that is connected at that moment and was connected before the note was recorded. A newly paired agent receives only notes recorded from then on. Watch notes reach the agent without the iPhone being nearby, because each device uploads its own notes.

#### Scenario: Agent paired after recording
- GIVEN a note was recorded at 9:00 and is still waiting to transcribe
- WHEN an agent pairs at 9:05 and the transcript is ready at 9:06
- THEN that agent receives no copy of the note

#### Scenario: Notes held for unlock
- GIVEN a note recorded while an agent was connected is held as "Unlock to transcribe" ([subscription.md](subscription.md))
- WHEN the person unlocks and it transcribes
- THEN the agent receives it then, as a new item

### Requirement: Zero agents still saves the note
With no agent connected, a note SHALL still upload and transcribe, and the person sees it as "Saved, no agent connected". It is not sent to an agent connected later, and there is no manual "send to agent" for it.

#### Scenario: Recording before connecting
- GIVEN no agent has ever been connected
- WHEN the person records a note
- THEN the transcript appears in the app and the note reads "Saved, no agent connected"
- AND an agent connected the next day never receives it

### Requirement: An item carries the transcript and when it was said
Each item an agent reads SHALL contain: its item number (used to acknowledge it), the note's ID, `created_at` (when recording started, from the recording device's clock, with that device's UTC offset), `received_at` (when the relay accepted the note, UTC), `duration` (seconds, measured by the server), and `transcription` (the full text). It contains no audio, device ID or name. Agents read relative times ("tomorrow at 9") from `created_at`.

#### Scenario: A note recorded offline
- GIVEN a note was recorded at 14:00 local time (UTC−5) with the watch offline, and uploaded at 19:00 local time
- WHEN the agent reads it
- THEN `created_at` reads 2026-11-01T14:00:00-05:00 and `received_at` reads 2026-11-02T00:00:00Z

### Requirement: Agents pull, then acknowledge
An agent's inbox check SHALL return its waiting items oldest first, at most 50 at a time, with a flag saying whether more are waiting. Items not acknowledged SHALL come back on every check. Acknowledging items SHALL delete that agent's copies only; acknowledging an item that is gone or not the agent's does nothing. Every call is safe to retry, and only a 401 means the agent has been disconnected.

#### Scenario: More than 50 waiting
- GIVEN 70 items are waiting for an agent
- WHEN it checks, acknowledges the 50 it got, and checks again
- THEN the first check says more are waiting, and the second returns the remaining 20

#### Scenario: Two agents, one acknowledges
- GIVEN "Grok Bot" and "Muse" each have a copy of a note
- WHEN Grok Bot acknowledges it
- THEN Muse's copy still comes back on Muse's next check

## Wake-up hooks

### Requirement: An agent can register its own wake-up hook
An agent MAY register one wake-up hook: an HTTPS URL with a public hostname (no IP addresses, localhost, `.local`, `.internal` or similar, and not the relay itself) and up to 8 headers totalling at most 4 KB. Headers that control the request itself (such as Host, Content-Type, Content-Length, User-Agent, Cookie) cannot be set. The relay SHALL store header values encrypted and never show them again, to the agent or the app. Setting a hook SHALL send one test ping right away and report its HTTP status. The agent can replace or remove its hook at any time.

#### Scenario: Registering a hook
- GIVEN an agent registers a hook with an Authorization header
- THEN the relay sends a test ping with event "ramble.test" and the text "Ramble test ping: your wake-up hook works. Nothing new to pick up, no action needed."
- AND the reply shows the hook URL, the header names, and the ping's status, but no header values

### Requirement: Hooks fire when a transcript is ready, with no transcript in them
When a new copy is made for an agent with a hook, the relay SHALL send a POST to the hook with the agent's headers and the body `{"event": "ramble.notes_waiting", "text": "New Ramble notes are waiting. Pull them from <relay>/inbox with your Ramble token, handle them, then ack.", "pull_url": "<relay>/inbox"}`. The ping SHALL never contain transcript text, note IDs or counts; the agent reads its notes with its own key as usual.

#### Scenario: A note arrives
- GIVEN an agent has a working hook
- WHEN the transcript of a new note is ready
- THEN the hook receives one "ramble.notes_waiting" ping, and the transcript is only available by checking the inbox

### Requirement: One ping per batch, best effort
After a ping, the relay SHALL send no further ping to that agent until it checks its inbox or 10 minutes pass, whichever comes first. Each ping is one attempt with a 5-second timeout, no retries and no redirects followed. A failed ping never affects the note, which stays waiting. Agents are told to keep a slow scheduled check as a fallback.

#### Scenario: A burst of notes
- GIVEN an agent with a hook has not checked in since its last ping 2 minutes ago
- WHEN three more transcripts are ready
- THEN no further ping is sent until it checks its inbox or 10 minutes have passed since the last ping

#### Scenario: A broken hook
- GIVEN the hook URL does not respond
- WHEN a note's transcript is ready
- THEN the ping is recorded as failed and the note stays waiting for the agent's next check

### Requirement: The app shows whether the hook works
The app SHALL show, on an agent's card, "Wakes up when a note arrives" when the agent has a hook whose last ping succeeded or that has not been pinged yet, and "Wake-up hook isn't answering" (amber) when the last ping got no 2xx response. The hook's URL and headers never reach the app.

#### Scenario: Hook fails
- GIVEN an agent's last ping timed out
- WHEN the person opens "Your agent"
- THEN its card reads "Wake-up hook isn't answering"

## Delivery status on the iPhone

### Requirement: Each note shows where it is
Once a note's transcript exists, the iPhone SHALL show its delivery in these words, on the list row and the note screen. Earlier states (recording, uploading, transcribing, held) are in [phone.md](phone.md) and [watch.md](watch.md).
- "Waiting for your agent" (amber): copies were made and at least one agent has not acknowledged it
- "Your agent has it" (green check): copies were made and none is still waiting
- "Saved, no agent connected": no copy was made because no agent was connected
- "Delivered to webhook": no agent copy, and the webhook accepted it
- "Didn't send" (red) with a "Retry" action: the webhook gave up
A failure is shown over any other state. The app refreshes these whenever it checks for transcripts ([phone.md](phone.md)).

#### Scenario: Picked up
- GIVEN a note reads "Waiting for your agent"
- WHEN the agent acknowledges it and the phone next checks
- THEN the note reads "Your agent has it", and the note screen reads "Picked up by your agent" with the time

#### Scenario: Not yet picked up
- GIVEN a note's copy is waiting
- WHEN the person opens the note
- THEN it reads "Sent, not picked up yet" and "Your agent picks it up next time it checks."

#### Scenario: Made before the agent connected
- GIVEN a note was saved with no agent connected and an agent is connected now
- WHEN the person opens the note
- THEN it reads "Not sent" with "It was made before your agent was connected."

### Requirement: Waiting counts every agent
With several agents connected, a note SHALL read "Waiting for your agent" until every agent that got a copy has acknowledged it, or its copy was deleted.

#### Scenario: One of two picked up
- GIVEN two agents got copies and only one has acknowledged
- THEN the note still reads "Waiting for your agent"

## Webhooks

### Requirement: One optional webhook destination
The person MAY set one webhook destination: an HTTPS URL with a hostname that is not localhost, a loopback, private or link-local IPv4 address, or an `.internal` host. The editor shows "Add destination" or "Edit destination", a signing secret, a link to the webhook docs, "Send test webhook", and, when editing, "Remove destination" (confirmed with "Transcripts will no longer be sent anywhere."). In onboarding, "Where should notes go?" offers "Your agent" and "Any webhook"; saving a webhook skips the connect step. Webhooks and agents are independent and can be used together.

#### Scenario: Invalid URL
- GIVEN the person types "http://example.com/hook"
- THEN the editor shows "URL must use HTTPS" and Save is disabled

### Requirement: The iPhone sends the webhook once it has the transcript
For every note whose transcript the iPhone receives while a destination is set, including watch notes, the iPhone SHALL POST one JSON body to the URL: `recording_id`, `created_at` (recording start, UTC), `duration` (seconds), `transcription`, and `device_id` (a random per-install ID, not tied to any account). The relay never sees the webhook URL or secret.

#### Scenario: Watch note to webhook
- GIVEN a webhook is set and the watch uploads a note directly to the relay
- WHEN the iPhone next pulls that note's transcript
- THEN the iPhone POSTs it to the webhook

### Requirement: Webhook requests are signed
Each webhook request SHALL carry `X-Webhook-Signature: sha256=<hex>`, the HMAC-SHA256 of the exact body keyed with the destination's signing secret. The secret is 24 random bytes, generated by the app, hidden until revealed, copyable, and replaceable with "Regenerate" after confirming "Your endpoint will need the new secret to accept requests."

#### Scenario: Verifying
- GIVEN an endpoint holds the signing secret
- WHEN it computes HMAC-SHA256 over the raw body
- THEN the result matches the header after "sha256="

### Requirement: Webhook retries are short, then the person decides
A webhook delivery SHALL succeed on any 2xx response within 10 seconds. Otherwise the iPhone SHALL try 3 times in total, waiting 30 seconds and then 2 minutes, then mark it "Didn't send". "Retry" on the note, or "Resend Webhook" in its menu, starts 3 fresh attempts. Pending webhooks survive the app closing and wait while the iPhone is locked.

#### Scenario: Endpoint down
- GIVEN the endpoint returns 500
- WHEN a note's transcript arrives
- THEN after the third failed attempt the note reads "Didn't send"
- AND the note's activity shows "Webhook failed after 3 attempts — HTTP 500"

### Requirement: Test webhooks are marked
"Send test webhook" SHALL POST the same shape with `"test": true`, a `recording_id` starting "test-", `duration` 0 and the text "This is a test webhook from Ramble.", and show "Test delivered" or "Failed — <reason>".

#### Scenario: Test succeeds
- GIVEN the endpoint returns 200
- WHEN the person taps "Send test webhook"
- THEN the editor shows "Test delivered"

### Requirement: Webhook health is shown
The app SHALL show the destination as green ("Last delivery succeeded") or red ("Last delivery failed") from the most recent note whose webhook finished, and yellow ("Webhook not yet tested") before any has.

#### Scenario: Last one failed
- GIVEN the most recent finished webhook delivery failed
- THEN the destination shows a red dot

## Retention and deletion

### Requirement: Agent copies are temporary
An agent's copy SHALL be deleted when that agent acknowledges it, when the agent is disconnected, when the person deletes waiting notes, or 30 days after the relay accepted it, whichever comes first. An expired copy is never returned, even before it is purged.

#### Scenario: Never picked up
- GIVEN an agent never checks in
- WHEN 30 days pass after a note was accepted
- THEN its copy is gone and no longer counts as waiting

### Requirement: The device copy is shorter-lived
The transcript the person's own devices read SHALL be deleted when the iPhone acknowledges it has saved it, or 7 days after it was ready, whichever comes first. Agent copies are not affected. The iPhone's local history is the only lasting copy ([phone.md](phone.md)).

#### Scenario: iPhone saves it
- GIVEN a transcript is ready and the iPhone pulls and saves it
- WHEN the iPhone acknowledges it
- THEN the server no longer holds that transcript for the person's devices, while agent copies remain until acknowledged

### Requirement: Delete waiting notes
The agent screen SHALL offer "Delete waiting notes", confirmed with "Notes your agent hasn't picked up are deleted from the relay. Your agent stays connected, and the copies on this phone stay." It SHALL delete every agent copy for this person and report "Deleted N waiting." or "Nothing was waiting." Agents stay connected.

#### Scenario: Deleting
- GIVEN 4 copies are waiting across two agents
- WHEN the person confirms "Delete waiting notes"
- THEN all 4 are deleted, both agents stay connected, and the button reads "Deleted 4 waiting."

### Requirement: Privacy copy matches what happens
The agent screen's "TEMPORARY BY DESIGN" note and any other delivery copy SHALL say: "Ramble's server is a relay, not an archive. Your audio is sent to a transcription provider and deleted as soon as the transcript is ready. Transcripts are deleted when your agent picks them up, or after 30 days. Your full history lives only on your iPhone." Copy saying audio never leaves the phone SHALL NOT appear.

#### Scenario: Reading the note
- GIVEN an agent is connected
- WHEN the person opens "Your agent"
- THEN the privacy note uses that wording
