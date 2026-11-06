# iPhone app

## Purpose
What the person sees and does in Ramble on iPhone: first launch, Home, recording, the notes list and note screen, playback, how history from the watch and Ramble's server comes together, Settings, stuck-note alerts, and Siri. Agents and delivery states are in [delivery.md](delivery.md); free notes, the unlock and fair use in [purchase.md](purchase.md); the watch in [watch.md](watch.md); the wire contract in [relay-api.md](relay-api.md).

## First launch

### Requirement: Onboarding steps
On first launch the app SHALL show onboarding as a sheet that cannot be swiped away: three intro beats ("Say it to your watch.", "Leave your phone behind.", "Your agent handles it.", each moving on after 6 seconds or by swiping, with "Get started" always visible), then "Where should notes go?", then connecting an agent ("Add your agent", [delivery.md](delivery.md)) unless skipped, then the watch step.

### Requirement: Consent line under "Get started"
Directly under "Get started" the intro SHALL show, in small type: "Ramble sends your recordings to a cloud service to turn them into text, then sends the text to your agent." followed by a "Privacy" link to the Privacy Policy, which names the transcription providers. Tapping "Get started" is the person's consent; there is no separate step or checkbox. Until it is tapped on this install, the phone SHALL NOT upload any note or connect the watch, so neither device sends audio before consent.

#### Scenario: Watch recorded before consent
- GIVEN the watch recorded two notes and the phone app has never run
- WHEN the person opens Ramble on iPhone and is on the intro beats
- THEN nothing has been uploaded and the watch still shows "Set up"
- AND after they tap "Get started", the watch is connected and its two notes upload

#### Scenario: Skipping the agent
- GIVEN the person is on "Where should notes go?"
- WHEN they tap "Set up later", or save a webhook from the "Any webhook" row
- THEN the watch step opens, and Back from it returns to "Where should notes go?"

### Requirement: Watch step
The watch step SHALL read "Now, put it on your watch." with "Open the Watch app", "No Apple Watch?" and "Later" when a paired watch lacks Ramble, "Ramble is on your watch." when it has it, and "No watch? No problem." when no watch is paired. Finishing SHALL show "You're all set" on Home for 2.4 seconds, and onboarding SHALL never show again on this install.

#### Scenario: Waiting for the install
- GIVEN a paired watch without Ramble
- WHEN the person is on the watch step
- THEN Continue stays disabled, rechecked every 2 seconds, and enables once the install lands

### Requirement: Setup can't reach Ramble
When the phone can't set itself up with Ramble's server (offline, or the server refuses new setups), it SHALL show "Ramble can't finish setting up right now. It will try again on its own." on Home under the status line, keep recording notes as "Waiting to send", and retry each time Ramble opens ([relay-api.md](relay-api.md) owns the daily limit).

#### Scenario: Daily setup limit reached
- GIVEN the server refuses new setups for the day
- WHEN the person finishes onboarding and records a note
- THEN the message shows, the note reads "Waiting to send", and setup completes on a later open

### Requirement: The phone connects the watch
The phone SHALL give the watch a credential that can only upload that watch's notes, read them back and read the account state, after the person taps "Get started" on first run, after a reinstall, when the paired watch changes, and whenever the watch says it has no working connection (no credential, or the server refused it), including when that message wakes the phone app in the background, with no control for the person ([watch.md](watch.md)). A reinstall that still finds the phone's earlier connection SHALL keep it (agents, free count and unlock stay); otherwise it starts fresh and agents must connect again ([delivery.md](delivery.md)).

#### Scenario: First phone launch
- GIVEN the watch has recorded notes but the phone app has never run
- WHEN the person opens Ramble on iPhone and taps "Get started"
- THEN the watch is connected and uploads its held notes

#### Scenario: Watch lost its connection
- GIVEN the phone has been set up for weeks and the watch app was reinstalled
- WHEN the watch app opens and tells the phone it has no connection
- THEN the phone gives it a new one without being opened, and the watch's waiting notes upload

## Home

### Requirement: Home layout
Home SHALL show the "Ramble" wordmark with an amber dot and a Settings button, one status line, the notes list, and the record control. On scroll the title and quiet status lines fade within 60 points; pills stay visible.

#### Scenario: Empty list
- GIVEN there are no notes
- WHEN Home is shown
- THEN it shows a watch illustration, "TRY SAYING", and one example phrase at a time, changing every 3.5 seconds (the first phrase only with Reduce Motion), and "Or record here" above the record button

### Requirement: Status line shows the single worst state
The status line SHALL show exactly one state, the first that applies below. Pills are tappable and open their fix; quiet states are plain text. Ages read "5m", "14h", "3d". Notes that couldn't transcribe, are too long, are over fair use, are silent, or are "Saved, no agent connected" never raise a pill.

| Order | State | Words | Kind | Tap |
|---|---|---|---|---|
| 1 | Webhook gave up | "1 note didn't send" / "N notes didn't send" · "Fix" (red) | Pill | Newest such note |
| 2 | Notes held for unlock, on either device | "1 note to unlock" / "N notes to unlock" · "Unlock" | Pill | Unlock screen |
| 3 | No agent and no webhook | "No agent connected" · "Connect" | Pill | Connect flow |
| 4 | Free notes nearly used | the line [purchase.md](purchase.md) defines | Pill | Unlock screen |
| 5 | A note has waited over 12 hours and the agent hasn't checked in within 12 hours | "Your agent hasn't checked in · 3d" (no age if never) | Pill | Your agent |
| 6 | A note has waited over 12 hours, agent checking in | "N notes waiting for your agent" | Pill | Your agent |
| 7 | Notes not yet accepted by the server | spinner, "Sending 1 note…" / "Sending N notes…" | Quiet | — |
| 8 | Notes transcribing | spinner, "Transcribing 1 note…" / "Transcribing N notes…" | Quiet | — |
| 9 | Notes waiting for the agent | "N waiting for your agent" (amber) | Quiet | — |
| 10 | Everything delivered | "All delivered · checked in 5m ago" ("just now" under a minute; "All delivered" if never); empty list: "Your agent is connected" or "Sending to your webhook" | Quiet | — |

#### Scenario: Out of free notes
- GIVEN one phone note and one watch note are held for unlock and no webhook has failed
- WHEN Home is shown
- THEN the status line reads "2 notes to unlock · Unlock"

## Recording on iPhone

### Requirement: Starting a recording
Tapping the mic button ("Record on iPhone") SHALL start recording with a heavy haptic, asking for microphone access the first time. A failed start SHALL play a warning haptic and show "Couldn't start recording" with "Ramble doesn't have microphone access. Turn it on in Settings to record." ("Open Settings", "OK") or "The microphone couldn't start. It may be in use by a call or another app."

#### Scenario: Microphone busy
- GIVEN a call holds the microphone
- WHEN the person taps record
- THEN the alert says "The microphone couldn't start. It may be in use by a call or another app."

### Requirement: While recording
While recording, the screen SHALL show the elapsed time, a stop button, live level bars, a discard button, and the input in use ("via iPhone", "via AirPods Pro", "via Headset"). Recording SHALL continue with the screen locked or Ramble in the background, at the format [transcription.md](transcription.md) sets so 60 minutes fits the upload limit.

#### Scenario: Pocketing the phone
- GIVEN the list is empty
- WHEN a recording has run for 3 seconds
- THEN "Pocket it — we'll keep listening" shows for 5 seconds, and locking the phone does not stop the recording

### Requirement: Stopping and discarding
Tapping stop, or a system interruption (a call, Siri, an alarm), SHALL save everything captured as a note at the top of the list, with a success haptic. A recording SHALL warn at 55:00 and stop at 60:00 like a tapped stop, as on the watch ([transcription.md](transcription.md) owns the cap). Discarding SHALL delete the audio with no note saved, asking first when the recording is over 30 seconds ("Discard recording?", "This will delete 1:12 of audio.", "Discard").

#### Scenario: Incoming call
- GIVEN a 4-minute recording is running
- WHEN a phone call comes in
- THEN the recording ends and a 4-minute note is saved and uploaded

#### Scenario: Approaching the cap
- GIVEN a recording is running
- WHEN it reaches 55:00
- THEN one notification haptic plays, the timer counts down the time left, and the line under it reads "Stops at 60:00"

### Requirement: Phone notes upload on their own
The phone SHALL upload each of its own notes under the note's ID, retrying 10 seconds after a failure and doubling up to every 5 minutes, and again whenever Ramble opens, until Ramble's server accepts it. When the upload reply carries the transcript, it shows at once.

#### Scenario: Offline recording
- GIVEN the phone is offline
- WHEN the person records a note
- THEN the row reads "Waiting to send", then "Transcribing…" once the server accepts it, and it is never counted twice

### Requirement: Held notes wait for their release
A note refused for unlock SHALL stop retrying until the unlock; one refused for fair use SHALL retry at the time the server gives and whenever Ramble opens; a rate-limited upload SHALL wait the time the server gives ([purchase.md](purchase.md), [relay-api.md](relay-api.md)).

#### Scenario: Unlock releases held notes
- GIVEN three phone notes read "Unlock to transcribe"
- WHEN the person completes the unlock
- THEN all three upload, oldest first, with no tap on any note

#### Scenario: Fair use resets
- GIVEN a phone note reads "Usage limit reached" with a reset on Dec 1
- WHEN Ramble opens on Dec 1
- THEN the note uploads

### Requirement: Refused for good
When the server refuses a note's audio for good, the phone SHALL stop retrying it, keep the audio, and never alert about it: "Too long to transcribe" for a recording over the length limit, "Couldn't send" otherwise ([relay-api.md](relay-api.md)).

#### Scenario: Damaged file
- GIVEN the server refuses a phone note's audio as unreadable
- WHEN the upload ends
- THEN the row reads "Couldn't send", the audio stays playable, and no retry or alert follows

## Notes list

### Requirement: List grouping and rows
The list SHALL group notes by day, newest first, under "Today", "Yesterday", or a date like "Thursday, November 6". Each row SHALL show the duration and time, the first line of the transcript, a caption when the note needs words, and a trailing icon.

#### Scenario: Row states
- GIVEN notes in different states
- WHEN the list is shown
- THEN each row reads as follows, and a transcribed watch note whose audio hasn't reached the phone shows "Audio on watch" when no other caption applies:

| State | Caption | Icon |
|---|---|---|
| Phone note not yet accepted | "Waiting to send" | tray |
| Watch note not yet accepted | "Waiting on your watch" | tray |
| Transcribing | spinner, "Transcribing…" | — |
| Held for unlock (either device) | "Unlock to transcribe" | lock, amber |
| Held for fair use | "Usage limit reached" | pause, amber |
| Refused for good | "Too long to transcribe" or "Couldn't send" | warning, red |
| Transcription failed | "Couldn't transcribe" | warning, red |
| Silent | "No speech detected" | quiet |
| No agent and no webhook when recorded | "Saved, no agent connected" | tray, grey |
| Webhook sending | — | spinner |
| Webhook gave up | "Didn't send" | warning, red |
| Agent copies waiting | — | tray, amber |
| Every agent copy removed unread | "Not picked up" | tray, grey |
| Picked up, or delivered to webhook | — | quiet check |

### Requirement: Deleting a note
The iPhone is the only full history: it SHALL keep every note's transcript and audio until the person deletes it or deletes the app. Swiping a row SHALL offer "Delete", which removes the note from this iPhone without asking; the note SHALL never come back from a later transcript or watch delivery, and agent copies are unaffected ([delivery.md](delivery.md)).

#### Scenario: Deleted before its transcript arrived
- GIVEN the person deleted a note that was still transcribing
- WHEN its transcript or watch audio reaches the phone later
- THEN the note does not reappear, and the server's copy for the phone is acknowledged

## Note screen

### Requirement: Note header and transcript
Tapping a row SHALL open the note screen titled "Recording" with the duration, "Thursday, November 6 at 9:12 AM", a status pill in the row's words, and the transcript. The transcript SHALL be selectable and clamped to 12 lines with "Show more" / "Show less"; "Copy" copies all of it and shows "Copied" for 1.5 seconds. Without a transcript the area reads "Waiting to send", "Transcribing…", "No transcript yet." or, for a silent note, "No speech detected", with no Copy button. The screen ends with a collapsed "Details" list of each logged step, its time to the second, and any HTTP status in green (under 300) or red.

#### Scenario: Copying
- GIVEN a note has a 40-line transcript
- WHEN the person taps "Copy"
- THEN the whole transcript is on the clipboard and "Copied" shows for 1.5 seconds

### Requirement: Playback
When the audio is on this iPhone, the note screen SHALL show a waveform player with play/pause, drag-to-seek, elapsed time and remaining time ("-1:02"); leaving the screen stops playback. Once the watch no longer keeps the audio ([watch.md](watch.md)), "Audio on watch" goes away and the screen shows "Audio file not available".

#### Scenario: Audio on the watch, watch app open
- GIVEN a note shows "Audio on watch" and Ramble is open on the watch
- WHEN the person taps it
- THEN the phone asks for the file, the watch sends it right away, and the player appears when it lands

#### Scenario: Audio on the watch, watch app closed
- GIVEN a note shows "Audio on watch" and Ramble isn't open on the watch
- WHEN the person taps it
- THEN the phone shows "Open Ramble on your watch to sync."

### Requirement: Delivery line
Under the player, the note screen SHALL show one line saying where the note is. Delivery states use exactly the words in [delivery.md](delivery.md) ("Waiting for your agent", "Your agent has it" with the first pickup time, "Not picked up", "Saved, no agent connected", "Nothing to send · no speech detected", "Delivered to webhook", "Didn't send" with "Retry"). Before delivery the line reads:

| State | Title | Detail | Action |
|---|---|---|---|
| Not accepted yet | "Waiting to send" | the last error and "Ramble will try again on its own." | — |
| Watch note not accepted yet | "Waiting on your watch" | — | — |
| Webhook send in progress | "Sending to your webhook…" | — | — |
| Transcribing | "Transcribing…" | "It goes out as soon as the transcript is ready." | — |
| Held for unlock | "Unlock to transcribe" | "This note is saved. It transcribes as soon as you unlock Ramble." | "Unlock" |
| Held for fair use | "Usage limit reached" | the detail in [purchase.md](purchase.md) ("… This note will transcribe on Dec 1. If this looks wrong, contact support.") | "Contact support" (an email to support@ramble.watch; purchase.md) |
| Audio unreadable | "Couldn't transcribe" | "Ramble couldn't turn this audio into text." | "Retry" |
| Transcription gave up | "Couldn't transcribe" | "Ramble couldn't reach a transcription service in time." | "Retry" |
| Failed after 3 retries | "Couldn't transcribe" | either detail above, then "Ramble tried 3 more times." | — |

#### Scenario: Unlock from a held note
- GIVEN a note shows "Unlock to transcribe"
- WHEN the person taps "Unlock"
- THEN the unlock screen opens ([purchase.md](purchase.md))

### Requirement: Retry a failed transcription
"Retry" and More → "Retry Transcription" SHALL re-upload the note's audio from this iPhone as a retry under the same note ID ([relay-api.md](relay-api.md)), up to 3 times per note; the note then reads "Transcribing…", or is held like any upload ([purchase.md](purchase.md)). When a watch note's audio is still only on the watch, Retry SHALL first fetch it as "Audio on watch" does, or show "Open Ramble on your watch to sync.".

#### Scenario: Third retry fails
- GIVEN a phone note has failed after 2 retries
- WHEN the person taps "Retry" and it fails again
- THEN the line reads "Couldn't transcribe" with "Ramble tried 3 more times." and no Retry button or menu item

### Requirement: More menu
The "More" menu SHALL offer "Delete" (confirmed with "Delete Recording" under "Delete this recording?", "This will permanently delete the recording and its transcript."), "Retry Transcription" while a "Couldn't transcribe" note has retries left, and "Resend Webhook" (the same delivery as webhook "Retry") when a webhook is set up and the note has a webhook result.

#### Scenario: Resend to the webhook
- GIVEN a webhook is set up and a note shows "Delivered to webhook"
- WHEN the person taps More → "Resend Webhook"
- THEN the note is sent to the webhook again

## History from the watch and the server

### Requirement: Watch notes merge by note ID
The phone SHALL build each watch note from what the watch sends (details and hold state, then audio) and the transcript from Ramble's server, matched by note ID; whichever arrives first creates the row, and a note SHALL never appear twice.

#### Scenario: Transcript first
- GIVEN the watch uploaded a note away from the phone
- WHEN the phone gets the transcript before the audio
- THEN the row shows the transcript and "Audio on watch", and the audio joins the same row when it arrives

### Requirement: When the phone checks in
When Ramble opens or returns to the foreground, periodically in the background as often as iOS allows, and when a message from the watch wakes it, the phone SHALL fetch waiting transcripts and acknowledge each once saved, refresh the delivery state of notes with agent copies waiting, and read its account state. When the server no longer knows a note, the phone SHALL keep the last state it saw.

#### Scenario: In the background
- GIVEN a watch note was transcribed while the phone app was closed
- WHEN Ramble runs in the background
- THEN the transcript is saved to the note and shows next time the person opens the app

## Stuck-note alerts

### Requirement: Phone alerts for stuck notes
The phone SHALL send at most one notification per kind, counting every note in it, no more than once per cooldown, cleared when nothing is left in that kind; each note alerts once. Accepted, held and refused-for-good notes never trigger "Not sent yet", and watch notes are alerted on the watch ([watch.md](watch.md)). Notification permission SHALL be asked once, in the foreground, after onboarding, when the first note exists.

| Kind | Fires when | Cooldown | Title | Body |
|---|---|---|---|---|
| Not sent | A phone note not accepted 6 hours after recording ended, or 6 hours after its release from a hold | 6 hours | "Not sent yet" | "1 note hasn't been sent yet. Open Ramble to send it." / "N notes haven't been sent yet. Open Ramble to send them." |
| Still waiting | Agent copies still waiting 12 hours after the note reached the server (checked only when Ramble runs) | 12 hours | "Still waiting for your agent" | "Your agent hasn't picked up 1 note since 9:12 AM." ("yesterday" or a weekday when older) |

#### Scenario: Alert while Ramble is closed
- GIVEN a phone note can't upload and the person leaves the app
- WHEN 6 hours pass, even if Ramble never runs again
- THEN "Not sent yet" appears

#### Scenario: First note
- GIVEN onboarding is finished and the list is empty
- WHEN the first note appears while Ramble is open
- THEN the system notification prompt shows

## Settings

### Requirement: Settings structure
Settings SHALL open as a sheet with "Done" and, in order: "Where notes go" ("Your agent", "Webhook"); the free-notes and unlock row ([purchase.md](purchase.md)); "Watch" ("Ramble on Apple Watch": "Installed" with a check, "Not installed yet. Install it from the Watch app." with "Install", or "No Apple Watch paired. You can record on iPhone."); "Transcription"; "App"; and a footer "Ramble <version> (<build>)" with "Privacy Policy" and "Terms of Use". It SHALL NOT offer a choice of transcription model, and release builds SHALL expose no debug screen, developer bypass key, or server address override.

#### Scenario: Tapping the version
- GIVEN a release build
- WHEN the person taps the version line 4 times
- THEN nothing opens

### Requirement: Agent row
The "Your agent" row SHALL read "Not connected" (grey) with no agent; with one, the check-in summary ("Checked in 2m ago · nothing waiting", "Checked in just now · 2 waiting") with a green dot, or "Hasn't checked in · 14h" with an amber dot when the agent is "Hasn't checked in" by the rule in [delivery.md](delivery.md); with several, the title "Your agents" and "N agents connected", or "<name> hasn't checked in". It opens the agent screen ([delivery.md](delivery.md)).

#### Scenario: One quiet agent
- GIVEN one agent last checked in 14 hours ago with notes waiting over 12 hours
- WHEN the person opens Settings
- THEN the row reads "Hasn't checked in · 14h" with an amber dot

### Requirement: Transcription settings
"Transcription" SHALL offer "Language" ("Auto-detect" first, then every language alphabetically), "Vocabulary" (hint "Names, jargon, and phrases the model might miss. Comma-separated.", up to 900 characters) and "Remove filler words"; the phone saves them to Ramble's server, and each note uses the options in effect when its first transcription attempt starts ([transcription.md](transcription.md)).

#### Scenario: Changing the language
- GIVEN Language is Auto-detect
- WHEN the person picks Spanish
- THEN a check marks Spanish, and notes from either device whose transcription starts afterward use it

### Requirement: App group and Your data
"App" SHALL offer "Appearance" (System, Light, Dark, applied at once), "How privacy works", and "Your data" (subtitle like "42 notes · 3h 5m"). "Your data" SHALL show the number of notes, total length, counts waiting to transcribe or that couldn't transcribe when above zero, "Export all notes (JSON)" (a share sheet with one JSON file of every note), and "Delete all data".

#### Scenario: How privacy works
- GIVEN the person opens "How privacy works"
- WHEN they read it
- THEN it uses the privacy wording in [delivery.md](delivery.md), adds that webhook transcripts go from the phone straight to their URL, and links to the privacy policy

#### Scenario: Delete all data
- GIVEN there are notes
- WHEN the person taps "Delete all data", then "Delete All" under "Delete all recordings?" ("This will permanently delete all recordings and transcriptions.")
- THEN every note is removed from this iPhone and none comes back later; agents, their waiting copies, the free count and the unlock are untouched ([delivery.md](delivery.md))

## Siri and Shortcuts

### Requirement: Recording intents
The phone SHALL offer three actions that open Ramble: "Start a Ramble" ("Start a Ramble", "Start recording with Ramble"), "Stop my Ramble" ("Stop my Ramble", "Stop recording with Ramble"), and "Ramble", which toggles ("Ramble", "Toggle Ramble"). Replies: "Recording started.", "Recording saved.", "No recording in progress.", or "Couldn't start recording." followed by the start-failure message.

#### Scenario: Start without the microphone
- GIVEN microphone access is denied
- WHEN the person says "Start a Ramble"
- THEN Siri says "Couldn't start recording. Ramble doesn't have microphone access. Turn it on in Settings to record."
