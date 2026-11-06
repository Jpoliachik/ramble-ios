# iPhone app

## Purpose
What the person sees and does in Ramble on iPhone: first launch, the Home screen and its status line, recording on the phone, the notes list and note screen, playback, how history from the watch and the server comes together, Settings, stuck-note alerts, and Siri. Connecting an agent is in delivery.md; free notes and the unlock purchase are in subscription.md; the watch is in watch.md.

## First launch

### Requirement: Onboarding steps
On first launch the app SHALL show onboarding as a sheet that cannot be swiped away, in this order: three intro beats, "Where should notes go?", connecting an agent (unless skipped), and getting the watch app. There SHALL be no speech-recognition permission step.

#### Scenario: Intro beats
- GIVEN Ramble has never been opened
- WHEN it launches
- THEN it shows three beats, "Say it to your watch.", "Leave your phone behind." and "Your agent handles it.", each moving on by itself after 6 seconds or by swiping
- AND "Get started" is always visible and goes to "Where should notes go?"

#### Scenario: Choosing where notes go
- GIVEN the person is on "Where should notes go?"
- WHEN they tap "Add your agent"
- THEN the connect step opens (delivery.md describes it)
- AND "Set up later", or saving a webhook from the "Any webhook" row, skips straight to the watch step
- AND Back from the watch step returns to whichever step came before it

#### Scenario: Watch step and finishing
- GIVEN the person reaches the watch step
- WHEN no watch is paired, THEN it says "No watch? No problem." and Continue is enabled
- WHEN the watch app is installed, THEN it says "Ramble is on your watch." and Continue is enabled
- WHEN a watch is paired without the app, THEN it says "Now, put it on your watch.", offers "Open the Watch app", keeps Continue disabled until the install lands (checked every couple of seconds), and offers "No Apple Watch?" and "Later" to finish anyway
- AND finishing shows a "You're all set" toast on Home for about 2.4 seconds, and onboarding never shows again on this install

### Requirement: Permissions are asked when needed
The app SHALL ask for microphone access on the first iPhone recording, and for notification permission only in the foreground, after onboarding, once at least one note exists.

#### Scenario: Notification prompt timing
- GIVEN onboarding is finished and the list is empty
- WHEN the first note appears and Ramble is in the foreground
- THEN the system notification prompt is shown, once

### Requirement: Watch gets its token from the phone
The phone SHALL give the watch its own scoped upload token after the app first runs, and a new one after a reinstall, without any action from the person (watch.md and relay-api.md describe the token).

#### Scenario: First phone launch
- GIVEN the watch has recorded notes but the phone app has never run
- WHEN the person opens Ramble on iPhone
- THEN the watch receives a token and starts uploading its held notes

## Home

### Requirement: Home layout
Home SHALL show the "Ramble" wordmark with an amber dot and a Settings button at the top, one status line under it, the notes list, and the record control at the bottom. On scroll, the title and quiet status lines fade within 60 points; status pills stay visible.

#### Scenario: Empty list
- GIVEN there are no notes
- WHEN Home is shown
- THEN it shows a watch illustration, "TRY SAYING", and one example phrase at a time, changing every 3.5 seconds (the first phrase only, with Reduce Motion on)
- AND "Or record here" appears above the record button

### Requirement: Status line shows the single worst state
The status line SHALL show exactly one state, the first that applies in this order, with the words below. Pill states are tappable and open their fix; quiet states are plain text.

| Order | State | Words | Kind | Tap |
|---|---|---|---|---|
| 1 | Notes that couldn't transcribe or whose webhook didn't send | "1 note didn't send" / "N notes didn't send" · "Fix" (red dot) | Pill | Opens the newest such note |
| 2 | Notes held because free notes ran out | "1 note to unlock" / "N notes to unlock" · "Unlock" (amber) | Pill | Opens the unlock screen (subscription.md) |
| 3 | No agent and no webhook set up | "No agent connected" · "Connect" (amber) | Pill | Opens the Connect flow |
| 4 | A note has waited over 12 hours for the agent and the agent hasn't checked in within 12 hours | "Your agent hasn't checked in · 3d" (age omitted if never) | Pill | Opens Your agent |
| 5 | A note has waited over 12 hours, but the agent is checking in | "N notes waiting for your agent" | Pill | Opens Your agent |
| 6 | Notes uploading or transcribing | spinner, "Sending 1 note…" / "Sending N notes…" | Quiet | — |
| 7 | Notes waiting for the agent (under 12 hours) | "N waiting for your agent" (amber dot) | Quiet | — |
| 8 | Everything delivered | "All delivered · checked in 5m ago" ("just now" under a minute; "All delivered" if never); on an empty list "Your agent is connected" or "Sending to your webhook" | Quiet | — |

Ages read "5m", "14h", "3d". Notes held for fair use and notes "Saved, no agent connected" never raise a pill on their own.

#### Scenario: Out of free notes
- GIVEN two notes are held with "Unlock to transcribe" and nothing has failed
- WHEN Home is shown
- THEN the status line reads "2 notes to unlock · Unlock"

## Recording on iPhone

### Requirement: Start and stop
Tapping the mic button ("Record on iPhone") SHALL start recording; while recording, the person SHALL see the elapsed time, a stop button, live level bars, a discard button, and the input in use ("via iPhone", "via AirPods Pro", "via Headset"). Start plays a heavy haptic, stop plays a success haptic, and a failed start plays a warning haptic.

#### Scenario: Stop saves the note
- GIVEN a recording is running
- WHEN the person taps stop
- THEN the note appears at the top of the list as "Transcribing…" and starts uploading (see "Phone notes upload directly")

#### Scenario: Discard
- GIVEN a recording has run for more than 30 seconds
- WHEN the person taps the discard button
- THEN "Discard recording?" asks for confirmation with "This will delete 1:12 of audio."
- AND "Discard" deletes the audio with no note saved
- AND under 30 seconds, discard happens without asking

#### Scenario: Microphone denied or busy
- GIVEN microphone access is denied, or a call or another app holds the microphone
- WHEN the person taps record
- THEN an alert "Couldn't start recording" says "Ramble doesn't have microphone access. Turn it on in Settings to record." (with "Open Settings" and "OK") or "The microphone couldn't start. It may be in use by a call or another app."

### Requirement: Recording continues in the background
A phone recording SHALL keep running when the screen locks or Ramble goes to the background, until the person stops it, it is interrupted, or it reaches the cap.

#### Scenario: Pocketing the phone
- GIVEN the list is empty and a recording has just started
- WHEN 3 seconds pass
- THEN "Pocket it — we'll keep listening" shows for 5 seconds
- AND locking the phone does not stop the recording

### Requirement: Interruptions end the recording and keep it
When the system interrupts a phone recording (a call, Siri, an alarm), the recording SHALL stop and save everything captured so far as a note, with the stop haptic.

#### Scenario: Incoming call
- GIVEN a 4-minute recording is running
- WHEN a phone call comes in
- THEN the recording ends and a 4-minute note is saved and uploaded

### Requirement: 60-minute cap
A phone recording SHALL stop and save at 60:00, with a warning haptic, and the timer SHALL show a cue as the cap approaches. There is no automatic second part.

#### Scenario: Approaching and reaching the cap
- GIVEN a recording is running
- WHEN it reaches 55:00, THEN the line under the timer reads "Stops at 60:00"
- WHEN it reaches 60:00, THEN recording stops, the warning haptic plays, and a 60:00 note is saved like any other

### Requirement: Phone notes upload directly
Each note recorded on the iPhone SHALL be uploaded by the phone to the relay under its own note ID, retried automatically until the relay confirms it is stored, and the phone SHALL keep the note's audio permanently as part of its history (relay-api.md has the upload contract).

#### Scenario: Offline recording
- GIVEN the phone is offline
- WHEN the person records a note
- THEN the note shows "Transcribing…" and its detail says the reason and "Ramble will try again on its own."
- AND the upload goes through when the phone is back online, without counting twice
- AND if the upload reply already carries the transcript, it shows at once without waiting for a pull

## Notes list

### Requirement: List grouping and rows
The list SHALL group notes by day, newest first, under "Today", "Yesterday", or a date like "Thursday, November 6". Each row SHALL show the duration and time, the first line of the transcript, a caption when the note needs words, and a trailing icon.

#### Scenario: Row states
- GIVEN notes in different states
- WHEN the list is shown
- THEN each row reads as follows:

| State | Caption | Icon |
|---|---|---|
| Uploading or transcribing | spinner, "Transcribing…" (in place of the transcript) | — |
| Watch note the server hasn't received yet | "Waiting on your watch" | tray |
| Out of free notes | "Unlock to transcribe" | lock, amber |
| Over fair use | "Paused for fair use" | pause, amber |
| Transcription failed for good | "Couldn't transcribe" | warning, red |
| Transcribed, no agent and no webhook when it was recorded | "Saved, no agent connected" | tray, grey |
| Sending to the webhook | "Sending…" | spinner |
| Webhook didn't accept it | "Didn't send" | warning, red |
| With the relay, agent hasn't picked it up | — | tray, amber |
| Agent picked it up, or webhook accepted it | — | quiet check |

- AND a note with a transcript whose watch audio hasn't reached the phone also shows "Audio on watch" as its caption, unless one of the captions above applies

### Requirement: Swipe to delete
Swiping a row SHALL offer "Delete", which removes the note's transcript and audio from this iPhone without asking.

#### Scenario: Deleted note stays deleted
- GIVEN the person deletes a note whose transcript hasn't reached the phone yet
- WHEN the transcript or the watch audio arrives later
- THEN the note does not come back

## Note screen

### Requirement: Note header and transcript
Tapping a row SHALL open the note screen titled "Recording", showing the duration, "Thursday, November 6 at 9:12 AM", a status pill in the same words as the row, then the transcript. Long transcripts show 12 lines with "Show more" / "Show less". The text is selectable, and "Copy" in the section header copies the whole transcript and shows "Copied" for 1.5 seconds.

#### Scenario: Waiting for a transcript
- GIVEN a note has no transcript yet
- WHEN the note screen opens
- THEN the transcript area reads "Transcribing...", "Waiting to transcribe...", or "No transcript yet." to match the note's state, and there is no Copy button
- AND a note transcribed with no words reads "No transcription available."

### Requirement: Playback
When the note's audio is on this iPhone, the note screen SHALL show a waveform player with play/pause, drag-to-seek on the waveform, elapsed time, and remaining time as "-1:02". Leaving the screen stops playback. A note with logged steps also ends with a collapsed "Details" list of each step, its time to the second, and any HTTP status in green (under 300) or red.

#### Scenario: Audio still on the watch
- GIVEN a watch note shows "Audio on watch" and the person taps it
- WHEN Ramble is open on the watch, THEN the phone asks for the file, the watch sends it right away, and the player appears when it lands
- WHEN Ramble isn't open on the watch, THEN the phone shows "Open Ramble on your watch to sync."

#### Scenario: Audio gone
- GIVEN the audio will never reach this phone (for example the watch was reset)
- WHEN the note screen opens
- THEN it shows "Audio file not available" and the transcript is unaffected

### Requirement: Delivery line
Under the player, the note screen SHALL show one line saying where the note is, with a detail and at most one action button:

| State | Title | Detail | Action |
|---|---|---|---|
| Uploading or transcribing | "Transcribing…" | "It goes out as soon as the transcript is ready.", or the last error plus "Ramble will try again on its own." | — |
| Out of free notes | "Unlock to transcribe" | "This note is saved. It transcribes as soon as you unlock Ramble." | "Unlock" (subscription.md) |
| Over fair use | "Paused for fair use" | wording owned by subscription.md | — |
| Failed for good | "Couldn't transcribe" | the reason | "Retry" |
| No agent, no webhook | "Saved, no agent connected" | "Connect an agent to send your next notes." | "Connect" |
| Webhook sending | "Sending…" | — | — |
| With the relay | "Sent, not picked up yet" | "Sent 9:12 AM. Your agent picks it up next time it checks." | — |
| Picked up | "Picked up by your agent" | "Sent 9:12 AM · picked up 9:15 AM" | — |
| Webhook accepted | "Delivered to webhook" | — | — |
| Webhook refused | "Webhook didn't accept it" | the error | "Retry" |

#### Scenario: Unlock clears the hold
- GIVEN a note shows "Unlock to transcribe"
- WHEN the person completes the unlock
- THEN the note goes back to "Transcribing…" by itself, with no tap on the note

#### Scenario: Connecting later doesn't send old notes
- GIVEN a note reads "Saved, no agent connected"
- WHEN the person connects an agent
- THEN that note keeps its state, and notes recorded from then on go to the agent

### Requirement: More menu
The "More" menu on the note screen SHALL offer "Retry Transcription" for a note that couldn't transcribe, "Resend Webhook" when a webhook is set up and the note has a webhook result, and "Delete". It SHALL NOT offer re-transcribing a note that has a transcript, or sending a note to the agent again.

#### Scenario: Delete from the note screen
- GIVEN the person chooses "Delete"
- WHEN "Delete this recording?" appears with "This will permanently delete the recording and its transcript."
- THEN "Delete Recording" removes it from this iPhone and returns to Home

## History from the watch and the server

### Requirement: The phone holds the only full history
The iPhone's local store SHALL be the only full history of notes, transcript and audio together; the server holds transcripts only until they are read (delivery.md), and the watch keeps only its own outstanding notes. Deleting the app deletes this history.

#### Scenario: Old notes
- GIVEN a note is six months old
- WHEN the person opens it on the phone
- THEN its transcript and audio are still there, though the server and the watch no longer have it

### Requirement: Two feeds merge by note ID
The phone SHALL build each watch note from two feeds, the server's transcript and the watch's details then audio, matched by note ID, so whichever arrives first creates the row and the rest fill it in; a note SHALL never appear twice.

#### Scenario: Watch details first
- GIVEN the watch records a note while the phone is nearby
- WHEN the watch's note details arrive
- THEN a row appears with the duration and time, and the transcript fills in when the phone pulls it

#### Scenario: Transcript first
- GIVEN the watch uploaded a note away from the phone
- WHEN the phone pulls the transcript before the watch's audio arrives
- THEN the row shows the transcript and "Audio on watch"
- AND the audio attaches to the same row when it arrives later, possibly hours later

### Requirement: When the phone pulls transcripts
The phone SHALL fetch waiting transcripts for its notes when Ramble opens or returns to the foreground, during background app refresh (as iOS allows, at most every 15 minutes), and whenever a message from the watch wakes it; it SHALL acknowledge each transcript once saved, so the server can delete its copy.

#### Scenario: Background refresh
- GIVEN a watch note was transcribed while the phone app was closed
- WHEN iOS runs Ramble's background refresh
- THEN the transcript is saved to the note and appears next time the person opens the app

## Stuck-note alerts

### Requirement: Phone alerts for stuck notes
The phone SHALL send at most one local notification per kind of problem, counting every note in it, no more than once per cooldown, with the alert cleared when nothing is left in that state. A note alerts only once; notes from before this version never alert.

| Kind | Fires when | Cooldown | Title | Body |
|---|---|---|---|---|
| Not sent | A note recorded on this iPhone has not reached the relay, or its webhook is still pending, 1 hour after recording | 6 hours | "Not sent yet" | "1 note hasn't been sent yet. Open Ramble to send it." / "N notes haven't been sent yet. Open Ramble to send them." |
| Needs you | A note couldn't transcribe or its webhook was refused, for 2 minutes | 6 hours | "Couldn't send" | "N notes couldn't be sent. Open Ramble to see why." |
| Not picked up | The agent hasn't picked up a note within 12 hours (checked only when Ramble runs) | 12 hours | "Not picked up" | "Your agent hasn't picked up 1 note since 9:12 AM." ("yesterday", or a weekday, for older notes) |

Notes held for unlock or fair use, and notes "Saved, no agent connected", SHALL never alert. Notes still on the watch are alerted by the watch (watch.md).

#### Scenario: Alert scheduled ahead
- GIVEN a phone note fails to upload and the person leaves the app
- WHEN an hour passes, even if Ramble never runs again
- THEN "Not sent yet" appears, because it was scheduled when Ramble went to the background

## Settings

### Requirement: Settings structure
Settings SHALL open as a sheet with "Done", and contain, in order:
- **Where notes go:** "Your agent" (subtitle "Not connected", "Connected", the agent's check-in summary, or "Hasn't checked in · 3h", with a grey, green or amber dot; opens Your agent, delivery.md) and "Webhook" ("Off" with "Add", or the URL's host with a green, red or grey dot; opens the webhook editor, delivery.md).
- **Unlock:** the free-notes count and unlock row, whose contents subscription.md defines.
- **Watch:** "Ramble on Apple Watch" with "Installed" and a check, "Not installed yet. Install it from the Watch app." with "Install" (opens the Watch app), or "No Apple Watch paired. You can record on iPhone."
- **Transcription:** "Language", "Vocabulary" and "Remove filler words" (transcription.md defines what they do).
- **App:** "Appearance" (System, Light, Dark), "How privacy works", and "Your data" (subtitle like "42 notes · 3h 5m").
- A footer with "Ramble 2.0 (51)", "Privacy Policy" and "Terms of Use".

There SHALL be no model picker, no on-device transcription option, and no subscription screen.

#### Scenario: Transcription settings
- GIVEN the person opens "Language"
- WHEN they pick one
- THEN the list shows "Auto-detect" first, then every language alphabetically, a check marks the choice, and it applies to notes recorded afterward
- AND Vocabulary (hint "Names, jargon, and phrases the model might miss. Comma-separated.") accepts at most 900 characters

### Requirement: How privacy works
"How privacy works" SHALL describe the redesign truthfully, including: "Ramble's server is a relay, not an archive. Your audio is sent to a transcription provider and deleted as soon as the transcript is ready. Transcripts are deleted when your agent picks them up, or after 30 days. Your full history lives only on your iPhone." It SHALL link to the full privacy policy, and SHALL NOT say audio stays on the device or never reaches Ramble's servers.

#### Scenario: Reading the sheet
- GIVEN the person opens "How privacy works"
- WHEN they read it
- THEN it says the above, and that webhook transcripts go from the phone straight to the URL they set

### Requirement: Your data
"Your data" SHALL show the number of notes, their total length, and counts of notes waiting to transcribe or that couldn't transcribe when above zero, plus "Export all notes (JSON)" and "Delete all data".

#### Scenario: Export
- GIVEN the person taps "Export all notes (JSON)"
- WHEN the share sheet opens
- THEN it offers one JSON file with the transcript and details of every note

#### Scenario: Delete all data
- GIVEN the person taps "Delete all data"
- WHEN "Delete all recordings?" warns "This will permanently delete all recordings and transcriptions." and they tap "Delete All"
- THEN every note's transcript and audio is removed from this iPhone
- AND agent connections and server copies are untouched ("Delete everything" in delivery.md covers those)

## Siri and Shortcuts

### Requirement: Recording intents
The phone SHALL offer three Siri and Shortcuts actions, each of which opens Ramble: "Start a Ramble" ("Start a Ramble", "Start recording with Ramble"), "Stop my Ramble" ("Stop my Ramble", "Stop recording with Ramble"), and "Ramble", which toggles ("Ramble", "Toggle Ramble").

#### Scenario: Start by voice
- GIVEN Ramble isn't recording
- WHEN the person says "Start a Ramble"
- THEN Ramble opens, recording starts, and Siri says "Recording started."
- AND if the start fails, Siri says "Couldn't start recording." followed by the reason

#### Scenario: Stop saves
- GIVEN a recording is running
- WHEN the person says "Stop my Ramble" or "Ramble"
- THEN the note is saved and uploaded like a tapped stop, and Siri says "Recording saved."
- AND with no recording running, "Stop my Ramble" gets "No recording in progress."
