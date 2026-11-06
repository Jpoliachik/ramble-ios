# iPhone app

## Purpose
What the person sees and does in Ramble on iPhone: first launch, Home and its status line, recording, the notes list and note screen, playback, how history from the watch and the server comes together, Settings, stuck-note alerts, and Siri. Connecting an agent and delivery meaning are in [delivery.md](delivery.md); free notes, the unlock and fair use are in [subscription.md](subscription.md); the watch is in [watch.md](watch.md); the wire contract is in [relay-api.md](relay-api.md).

## First launch

### Requirement: Onboarding steps
On first launch the app SHALL show onboarding as a sheet that cannot be swiped away, in this order: three intro beats ("Say it to your watch.", "Leave your phone behind.", "Your agent handles it.", each moving on after 6 seconds or by swiping, with "Get started" always visible), "Where should notes go?", connecting an agent (unless skipped), and getting the watch app. With the watch app installed the last step reads "Ramble is on your watch.", with no watch paired "No watch? No problem.", and finishing shows "You're all set" on Home for 2.4 seconds; onboarding never shows again on this install.

#### Scenario: Choosing where notes go
- GIVEN the person is on "Where should notes go?"
- WHEN they tap "Add your agent"
- THEN the connect step opens ([delivery.md](delivery.md))
- AND "Set up later", or saving a webhook from the "Any webhook" row, goes straight to the watch step, and Back from there returns to the step before it

#### Scenario: Watch app not installed
- GIVEN a watch is paired without Ramble on it
- WHEN the person reaches the watch step
- THEN it says "Now, put it on your watch." and offers "Open the Watch app", "No Apple Watch?" and "Later"
- AND Continue stays disabled until the install lands, checked every 2 seconds

### Requirement: The phone provisions the watch
The phone SHALL give the watch its scoped token after the app first runs and after a reinstall, and SHALL replace it automatically when the paired watch changes, with no control for the person ([watch.md](watch.md), [relay-api.md](relay-api.md)).

#### Scenario: First phone launch
- GIVEN the watch has recorded notes but the phone app has never run
- WHEN the person opens Ramble on iPhone
- THEN the watch receives a token and uploads its held notes

## Home

### Requirement: Home layout
Home SHALL show the "Ramble" wordmark with an amber dot and a Settings button, one status line, the notes list, and the record control. On scroll the title and quiet status lines fade within 60 points; pills stay visible.

#### Scenario: Empty list
- GIVEN there are no notes
- WHEN Home is shown
- THEN it shows a watch illustration, "TRY SAYING", and one example phrase at a time, changing every 3.5 seconds (the first phrase only with Reduce Motion)
- AND "Or record here" appears above the record button

### Requirement: Status line shows the single worst state
The status line SHALL show exactly one state, the first that applies in this order. Pills are tappable and open their fix; quiet states are plain text. Ages read "5m", "14h", "3d". Notes "Saved, no agent connected", "Over fair use" or "No speech detected" never raise a pill.

| Order | State | Words | Kind | Tap |
|---|---|---|---|---|
| 1 | Notes that couldn't transcribe or whose webhook gave up | "1 note didn't send" / "N notes didn't send" · "Fix" (red) | Pill | Newest such note |
| 2 | Phone notes held for unlock | "1 note to unlock" / "N notes to unlock" · "Unlock" | Pill | Unlock screen |
| 3 | No agent and no webhook | "No agent connected" · "Connect" | Pill | Connect flow |
| 4 | Free notes nearly used, or fair use near its limit | the line [subscription.md](subscription.md) defines | Pill | Unlock screen or Settings |
| 5 | A note has waited over 12 hours and the agent hasn't checked in within 12 hours | "Your agent hasn't checked in · 3d" (no age if never) | Pill | Your agent |
| 6 | A note has waited over 12 hours, agent checking in | "N notes waiting for your agent" | Pill | Your agent |
| 7 | Notes waiting to send or transcribing | spinner, "Sending 1 note…" / "Sending N notes…" | Quiet | — |
| 8 | Notes waiting for the agent | "N waiting for your agent" (amber) | Quiet | — |
| 9 | Everything delivered | "All delivered · checked in 5m ago" ("just now" under a minute; "All delivered" if never); empty list: "Your agent is connected" or "Sending to your webhook" | Quiet | — |

#### Scenario: Out of free notes
- GIVEN two phone notes are held with "Unlock to transcribe" and nothing has failed
- WHEN Home is shown
- THEN the status line reads "2 notes to unlock · Unlock"

## Recording on iPhone

### Requirement: Starting a recording
Tapping the mic button ("Record on iPhone") SHALL start recording with a heavy haptic, asking for microphone access the first time; a failed start SHALL play a warning haptic and show "Couldn't start recording" with the reason.

#### Scenario: Microphone denied or busy
- GIVEN microphone access is denied, or a call or another app holds the microphone
- WHEN the person taps record
- THEN the alert says "Ramble doesn't have microphone access. Turn it on in Settings to record." (with "Open Settings" and "OK"), or "The microphone couldn't start. It may be in use by a call or another app."

### Requirement: While recording
While recording, the screen SHALL show the elapsed time, a stop button, live level bars, a discard button, and the input in use ("via iPhone", "via AirPods Pro", "via Headset"). Recording SHALL continue with the screen locked or Ramble in the background.

#### Scenario: Pocketing the phone
- GIVEN the list is empty
- WHEN a recording has run for 3 seconds
- THEN "Pocket it — we'll keep listening" shows for 5 seconds, and locking the phone does not stop the recording

### Requirement: Stopping and discarding
Tapping stop, or a system interruption (a call, Siri, an alarm), SHALL save everything captured as a note with a success haptic, at the top of the list; discarding SHALL delete the audio with no note saved, asking first when the recording is over 30 seconds.

#### Scenario: Incoming call
- GIVEN a 4-minute recording is running
- WHEN a phone call comes in
- THEN the recording ends and a 4-minute note is saved and uploaded

#### Scenario: Discard a long recording
- GIVEN a recording has run 1:12
- WHEN the person taps discard
- THEN "Discard recording?" asks "This will delete 1:12 of audio." and "Discard" deletes it

### Requirement: 60-minute cap
A phone recording SHALL warn at 55:00 and stop at 60:00 like a tapped stop, the same way as on the watch; [transcription.md](transcription.md) owns what the cap means on the server.

#### Scenario: Approaching the cap
- GIVEN a recording is running
- WHEN it reaches 55:00
- THEN one notification haptic plays, the timer counts down the time left, and the line under it reads "Stops at 60:00"

### Requirement: Phone notes upload on their own
The phone SHALL upload each of its own notes under the note's ID, retrying 10 seconds after a failure and doubling up to every 5 minutes, and again whenever Ramble opens, until the relay accepts it. When the upload reply carries the transcript, it shows at once.

#### Scenario: Offline recording
- GIVEN the phone is offline
- WHEN the person records a note
- THEN the row reads "Waiting to send", and the note screen gives the reason and "Ramble will try again on its own."
- AND once the relay accepts it the row reads "Transcribing…", and it is never counted twice

### Requirement: Held notes wait for their release
A phone note refused for unlock SHALL stop retrying until the unlock; one refused for fair use SHALL retry at the time the relay gives and whenever Ramble opens; a rate-limited upload SHALL wait the time the relay gives ([subscription.md](subscription.md)).

#### Scenario: Unlock releases held notes
- GIVEN three phone notes read "Unlock to transcribe"
- WHEN the person completes the unlock
- THEN all three upload, oldest first, with no tap on any note

## Notes list

### Requirement: List grouping and rows
The list SHALL group notes by day, newest first, under "Today", "Yesterday", or a date like "Thursday, November 6". Each row SHALL show the duration and time, the first line of the transcript, a caption when the note needs words, and a trailing icon.

#### Scenario: Row states
- GIVEN notes in different states
- WHEN the list is shown
- THEN each row reads as follows, and a transcribed watch note whose audio hasn't reached the phone shows "Audio on watch" when no other caption applies:

| State | Caption | Icon |
|---|---|---|
| Phone note not yet accepted by the relay | "Waiting to send" | tray |
| Watch note the server hasn't accepted yet, including watch notes held for unlock | "Waiting on your watch" | tray |
| Transcribing | spinner, "Transcribing…" | — |
| Phone note held for unlock | "Unlock to transcribe" | lock, amber |
| Held for fair use | "Over fair use" | pause, amber |
| Failed for good | "Couldn't transcribe" | warning, red |
| Silent | "No speech detected" | quiet |
| No agent connected when it was recorded, no webhook | "Saved, no agent connected" | tray, grey |
| Webhook sending | — | spinner |
| Webhook gave up | "Didn't send" | warning, red |
| Agent copies waiting | — | tray, amber |
| Every agent copy removed unread | "Not picked up" | tray, grey |
| Picked up by an agent, or webhook accepted | — | quiet check |

### Requirement: Deleting a note
The iPhone is the only full history: it SHALL keep every note's transcript and audio until the person deletes it or deletes the app ([delivery.md](delivery.md) covers the server's copies). Swiping a row SHALL offer "Delete", which removes the note's transcript and audio from this iPhone without asking; the note SHALL never come back from a later transcript or watch delivery, and agent copies are unaffected ([delivery.md](delivery.md)).

#### Scenario: Deleted before its transcript arrived
- GIVEN the person deleted a note that was still transcribing
- WHEN its transcript or watch audio reaches the phone later
- THEN the note does not reappear, and the server's copy for the phone is acknowledged

## Note screen

### Requirement: Note header and transcript
Tapping a row SHALL open the note screen titled "Recording": duration, "Thursday, November 6 at 9:12 AM", a status pill in the row's words, then the transcript, clamped to 12 lines with "Show more" / "Show less". The text is selectable, and "Copy" copies all of it and shows "Copied" for 1.5 seconds. A collapsed "Details" list at the end shows each logged step, its time to the second, and any HTTP status in green (under 300) or red.

#### Scenario: No transcript yet
- GIVEN a note has no transcript
- WHEN the note screen opens
- THEN the transcript area reads "Waiting to transcribe...", "Transcribing..." or "No transcript yet." to match its state, or "No speech detected" for a silent note ([transcription.md](transcription.md)), with no Copy button

### Requirement: Playback
When the audio is on this iPhone, the note screen SHALL show a waveform player with play/pause, drag-to-seek, elapsed time and remaining time ("-1:02"); leaving the screen stops playback.

#### Scenario: Audio on the watch, watch app open
- GIVEN a note shows "Audio on watch" and Ramble is open on the watch
- WHEN the person taps it
- THEN the phone asks for the file, the watch sends it right away, and the player appears when it lands

#### Scenario: Audio on the watch, watch app closed
- GIVEN a note shows "Audio on watch" and Ramble isn't open on the watch
- WHEN the person taps it
- THEN the phone shows "Open Ramble on your watch to sync."

#### Scenario: Audio never arrives
- GIVEN the watch no longer keeps the audio ([watch.md](watch.md) owns how long)
- WHEN the note screen opens
- THEN "Audio on watch" is gone, the screen shows "Audio file not available", and the transcript is unaffected

### Requirement: Delivery line
Under the player, the note screen SHALL show one line saying where the note is, with a detail and at most one action. The states are defined in [delivery.md](delivery.md); these are the words:

| State | Title | Detail | Action |
|---|---|---|---|
| Phone note not accepted yet | "Waiting to send" | "It goes out as soon as the phone is online.", or the last error plus "Ramble will try again on its own." | — |
| Transcribing | "Transcribing…" | "It goes out as soon as the transcript is ready." | — |
| Held for unlock | "Unlock to transcribe" | "This note is saved. It transcribes as soon as you unlock Ramble." | "Unlock" |
| Held for fair use | "Over fair use" | "This note will transcribe on Dec 1." (the reset date) | — |
| Failed for good | "Couldn't transcribe" | the reason | — |
| Silent | "Nothing to send · no speech detected" | — | — |
| No agent, no webhook | "Saved, no agent connected" | "Connect an agent to send your next notes."; once one is connected: "It was made before your agent was connected." | "Connect" (until one is connected) |
| Agent copies waiting | "Sent, not picked up yet" | "Sent 9:12 AM. Your agent picks it up next time it checks." | — |
| Picked up | "Picked up by your agent" | "Sent 9:12 AM · picked up 9:15 AM" (first pickup) | — |
| All copies removed unread | "Not picked up" | "Your agent didn't pick it up before it was removed." | — |
| Webhook accepted | "Delivered to webhook" | — | — |
| Webhook gave up | "Webhook didn't accept it" | the error | "Retry" |

#### Scenario: Unlock from a held note
- GIVEN a phone note shows "Unlock to transcribe"
- WHEN the person taps "Unlock"
- THEN the unlock screen opens ([subscription.md](subscription.md))

### Requirement: More menu
The "More" menu SHALL offer "Resend Webhook" when a webhook is set up and the note has a webhook result, and "Delete".

#### Scenario: Delete from the note screen
- GIVEN the note screen is open
- WHEN the person taps More → "Delete", then "Delete Recording" under "Delete this recording?" ("This will permanently delete the recording and its transcript.")
- THEN the note is removed from this iPhone as in "Deleting a note" and Home is shown

## History from the watch and the server

### Requirement: Watch notes merge by note ID
The phone SHALL build each watch note from what the watch sends (details, then audio) and the transcript from the server, matched by note ID; whichever arrives first creates the row and a note SHALL never appear twice.

#### Scenario: Transcript first
- GIVEN the watch uploaded a note away from the phone
- WHEN the phone pulls the transcript before the audio arrives
- THEN the row shows the transcript and "Audio on watch", and the audio joins the same row when it arrives

### Requirement: When the phone pulls transcripts
The phone SHALL fetch waiting transcripts when Ramble opens or returns to the foreground, when iOS runs its background refresh, and when a message from the watch wakes it, and SHALL acknowledge each transcript once saved.

#### Scenario: Background refresh
- GIVEN a watch note was transcribed while the phone app was closed
- WHEN iOS runs Ramble's background refresh
- THEN the transcript is saved to the note and shows next time the person opens the app

## Stuck-note alerts

### Requirement: Phone alerts for stuck notes
The phone SHALL send at most one notification per kind, counting every note in it, no more than once per cooldown, cleared when nothing is left in that kind; each note alerts once. Notes the relay accepted, held notes, and watch notes (alerted on the watch, [watch.md](watch.md)) never trigger "Not sent yet". Notification permission is asked in the foreground, after onboarding, once a note exists.

| Kind | Fires when | Cooldown | Title | Body |
|---|---|---|---|---|
| Not sent | A phone note the relay hasn't accepted 6 hours after recording ended | 6 hours | "Not sent yet" | "1 note hasn't been sent yet. Open Ramble to send it." / "N notes haven't been sent yet. Open Ramble to send them." |
| Not picked up | Agent copies of a note still waiting 12 hours after it was sent (checked only when Ramble runs) | 12 hours | "Not picked up" | "Your agent hasn't picked up 1 note since 9:12 AM." ("yesterday" or a weekday when older) |

#### Scenario: Alert while Ramble is closed
- GIVEN a phone note can't upload and the person leaves the app
- WHEN 6 hours pass, even if Ramble never runs again
- THEN "Not sent yet" appears

## Settings

### Requirement: Settings structure
Settings SHALL open as a sheet with "Done" and these groups, in order: "Where notes go"; the free-notes and unlock row ([subscription.md](subscription.md)); "Watch" ("Ramble on Apple Watch": "Installed" with a check, "Not installed yet. Install it from the Watch app." with "Install", or "No Apple Watch paired. You can record on iPhone."); "Transcription"; "App"; and a footer reading "Ramble <version> (<build>)" with "Privacy Policy" and "Terms of Use". Settings SHALL NOT offer a choice of transcription model. Release builds SHALL expose no debug screen, developer bypass key, or relay address override.

#### Scenario: Where notes go
- GIVEN the person opens Settings
- WHEN they look at "Where notes go"
- THEN "Your agent" reads "Not connected", "Connected", the agent's check-in summary, or "Hasn't checked in · 3h" (grey, green or amber dot); with several agents the row is "Your agents" with "N agents connected" or "<name> hasn't checked in"
- AND "Webhook" reads "Off" with "Add", or the URL's host with a green, red or grey dot; both open their screens in [delivery.md](delivery.md)

#### Scenario: Tapping the version
- GIVEN a release build
- WHEN the person taps the version line repeatedly
- THEN nothing opens

### Requirement: Transcription settings
"Transcription" SHALL offer "Language" ("Auto-detect" first, then every language alphabetically), "Vocabulary" (hint "Names, jargon, and phrases the model might miss. Comma-separated.", up to 900 characters) and "Remove filler words"; the phone saves them to the relay, and they apply to notes whose transcription starts afterward ([transcription.md](transcription.md)).

#### Scenario: Changing the language
- GIVEN Language is Auto-detect
- WHEN the person picks Spanish
- THEN a check marks Spanish, and the next notes transcribed, from either device, use it

### Requirement: App group
"App" SHALL offer "Appearance" (System, Light, Dark, applied at once), "How privacy works", and "Your data" (subtitle like "42 notes · 3h 5m").

#### Scenario: How privacy works
- GIVEN the person opens "How privacy works"
- WHEN they read it
- THEN it uses the privacy wording in [delivery.md](delivery.md), adds that webhook transcripts go from the phone straight to the URL they set, and links to the full privacy policy

### Requirement: Your data
"Your data" SHALL show the number of notes, total length, and counts waiting to transcribe or that couldn't transcribe when above zero, plus "Export all notes (JSON)" (a share sheet with one JSON file of every note's transcript and details) and "Delete all data".

#### Scenario: Delete all data
- GIVEN there are notes
- WHEN the person taps "Delete all data", then "Delete All" under "Delete all recordings?" ("This will permanently delete all recordings and transcriptions.")
- THEN every note is removed from this iPhone and none comes back from a later feed
- AND agents, their waiting copies, the free count and the unlock are untouched; server-side deletion is in [delivery.md](delivery.md)

## Siri and Shortcuts

### Requirement: Recording intents
The phone SHALL offer three actions, each of which opens Ramble: "Start a Ramble" ("Start a Ramble", "Start recording with Ramble"), "Stop my Ramble" ("Stop my Ramble", "Stop recording with Ramble"), and "Ramble", which toggles ("Ramble", "Toggle Ramble"). "Stop my Ramble" with nothing running answers "No recording in progress."

#### Scenario: Start by voice
- GIVEN Ramble isn't recording
- WHEN the person says "Start a Ramble"
- THEN recording starts and Siri says "Recording started.", or "Couldn't start recording." and the reason

#### Scenario: Stop by voice
- GIVEN a recording is running
- WHEN the person says "Stop my Ramble"
- THEN the note is saved like a tapped stop and Siri says "Recording saved."
