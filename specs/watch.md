# Watch

## Purpose
What the person experiences on Apple Watch: recording a note, the home screen and its states, the short list of recent notes, and how the watch sends each note straight to Ramble's server and tells the person when one is stuck. The watch works without the iPhone nearby; the iPhone holds the full history (see phone.md).

## Home screen

### Requirement: One button, one bar
The home screen SHALL show one record button centered on the full screen and one bar along the bottom edge, with nothing above the button. The button SHALL be the only way to start and stop recording on this screen; tapping anywhere else SHALL NOT start or stop a recording.

#### Scenario: At rest
- GIVEN the watch app is open and nothing is recording
- WHEN the person looks at the watch
- THEN the button shows an amber ring with a filled amber disc
- AND the bar shows the history button at the right, plus a badge if any note has one (see "History badge")
- AND the bar's left side is empty unless an alert is active

#### Scenario: The button never moves
- GIVEN an alert appears or disappears in the bar
- WHEN the bar changes
- THEN the button stays in the same place and at the same size

#### Scenario: VoiceOver labels
- GIVEN VoiceOver is on
- WHEN the person moves through the home screen
- THEN it reads the button as "Record" (or "Stop recording" while recording), then the alert by its detail title with the hint "Double tap for help", then the history button as "Recent"

### Requirement: Words rule for the bar
Bar alerts SHALL be one icon plus at most 8 characters, counting spaces, and SHALL end at least 12pt before the history button on every watch size. Only one alert SHALL show at a time. A message that does not fit SHALL get a shorter word, never a smaller font or a second line. Full sentences SHALL live only on the alert's detail screen. While recording, an alert SHALL show only its icon.

#### Scenario: Alert with a detail screen
- GIVEN the "No phone" alert is active
- WHEN the person taps it
- THEN a detail screen opens with an icon and title, what happened, and how to fix it
- AND the bar alert shows a small chevron because it opens a detail screen

### Requirement: Bar alerts and their order
The watch SHALL show at most one bar alert, chosen in this order: "Mic off", "Mic busy", "No phone", "Set up", "Unlock", "Limit". "Mic off" and "Mic busy" SHALL be red because nothing can be recorded; the others SHALL be gray because recording still works.

| Alert | When | Detail title | Detail text |
|---|---|---|---|
| "Mic off" | Microphone permission is off; checked at launch and on every return to the foreground | "Microphone is off" | "Ramble can't hear you, so nothing gets recorded." / "On your watch, open Settings, then Privacy & Security, then Microphone, and turn on Ramble." |
| "Mic busy" | For 3 seconds after a start fails for any reason other than permission | none (tapping the button again is the fix) | none |
| "No phone" | The paired iPhone does not have Ramble installed | "Ramble isn't on your iPhone" | "Your notes are safe on this watch, but they can't reach your agent yet." / "Install Ramble on your iPhone and open it once. Waiting notes will send on their own." |
| "Set up" | Ramble is on the iPhone but the watch has no working token (the phone app has never run, or the token was revoked or replaced) | "Open Ramble on your iPhone" | "Your notes are safe on this watch, but they can't send yet." / "Open Ramble on your iPhone once. Waiting notes will send on their own." |
| "Unlock" | At least one note is held because the free notes are used up | "Unlock to transcribe" | "You've used your free notes. Your notes are safe on this watch." / "Unlock Ramble on your iPhone and they'll transcribe on their own." |
| "Limit" | At least one note is held because of fair use | "Over fair use" | "Your notes are safe on this watch, but they won't be transcribed for now." / "Open Ramble on your iPhone for details." |

#### Scenario: Two alerts at once
- GIVEN the microphone permission is off and a note is held for unlock
- WHEN the home screen shows
- THEN the bar shows only "Mic off"

### Requirement: First launch hint
Until the first note is ever saved on this watch, the button SHALL show a soft amber ring that breathes out from it every 2.2 seconds, unless the microphone is off. Once a note has been saved, the ring SHALL never return, even after every note has aged out of the list.

#### Scenario: First note
- GIVEN the watch has never saved a note
- WHEN the person records and stops their first note
- THEN the breathing ring stops for good

### Requirement: History badge
The history button SHALL carry at most one mark, highest first: a red dot if any note needs the person (stuck, held, failed, or lost and not yet seen); otherwise a spinning ring while any note is uploading or being transcribed; otherwise a still gray dot if any note is waiting to upload; otherwise nothing. The history button and its badge SHALL be hidden while recording.

#### Scenario: Watch offline
- GIVEN the watch has no connection and two notes are waiting to upload
- WHEN the person looks at the home screen
- THEN the history button shows a still gray dot, not red

#### Scenario: Reduce Motion
- GIVEN Reduce Motion is on and a note is uploading
- WHEN the home screen shows
- THEN a still gray dot stands in for the spinning ring

## Recording

### Requirement: Instant start, any time
A tap on the button SHALL start recording on the watch at once, whatever the iPhone is doing, without waiting on the iPhone, the network, or a token. Starting SHALL play the start haptic and replace the disc with three amber level bars that follow the person's voice, and SHALL hide the history button. The bar SHALL show the elapsed time in amber serif digits (for example "1:04"), which VoiceOver reads as "Recording, 1 minute, 4 seconds". Double-tapping the fingers, on watches that support it, SHALL act exactly like tapping the button.

#### Scenario: Start with the phone away
- GIVEN the iPhone is out of range and the watch is offline
- WHEN the person taps the button
- THEN recording starts and the start haptic plays

#### Scenario: The phone can't stop the watch
- GIVEN the watch is recording
- WHEN the iPhone starts or stops its own recording
- THEN the watch keeps recording

### Requirement: Recording keeps going with the wrist down
Once started, a recording SHALL keep running when the person lowers their wrist, the screen sleeps, or the app goes to the background, until it is stopped.

#### Scenario: Wrist down mid-note
- GIVEN the person is recording
- WHEN they lower their wrist for two minutes and raise it again
- THEN the recording is still running and the timer shows the full elapsed time

### Requirement: Stop and save
Stopping SHALL save the note on the watch immediately and play the success haptic. The bars SHALL collapse into the disc and a check SHALL draw itself inside it and be gone by 0.8 seconds. Every stop SHALL look and feel the same however it happened: the button, double-tap, Siri, the 60-minute cap, or something else taking the microphone.

#### Scenario: Stop with the button
- GIVEN the person is recording
- WHEN they tap the button
- THEN the success haptic plays, the check draws in, and the history button fades back in

#### Scenario: A call takes the microphone
- GIVEN the person is recording
- WHEN a phone call or Siri takes the microphone
- THEN everything said so far is saved as a note, with the same haptic and check

#### Scenario: Tap during the check
- GIVEN the check is showing after a stop
- WHEN the person taps the button
- THEN a new recording starts at once

### Requirement: 60-minute cap
A recording SHALL stop and save at 60:00. From 55:00 the timer SHALL show the time left with a minus sign (for example "−4:59"), and one notification haptic SHALL play at 55:00. The stop at 60:00 SHALL be a normal stop. Nothing SHALL continue into a second note.

#### Scenario: Nearing the cap
- GIVEN a recording reaches 55:00
- WHEN the timer updates
- THEN one haptic plays and the timer reads "−5:00", counting down

#### Scenario: Hard stop
- GIVEN a recording reaches 60:00
- WHEN the cap is hit
- THEN the recording stops and is saved, the success haptic plays, and no new recording starts

### Requirement: Microphone permission
The first tap SHALL show the system microphone prompt with the text "Ramble records what you say on your watch and sends it to your agent." and SHALL start recording if the person allows it. While permission is off, the button SHALL look dimmed and a tap SHALL play the failure haptic, shake the "Mic off" alert sideways, and not record.

#### Scenario: Permission denied
- GIVEN microphone permission is off
- WHEN the person taps the button
- THEN the failure haptic plays, "Mic off" shakes, and nothing records

### Requirement: Microphone busy
When a start fails for any reason other than permission, the watch SHALL play the failure haptic and show "Mic busy" in red for 3 seconds.

#### Scenario: Another app has the mic
- GIVEN another app holds the microphone
- WHEN the person taps the button
- THEN the failure haptic plays and "Mic busy" shows for 3 seconds, then disappears

## Recent notes on the watch

### Requirement: Only this watch's notes
The Recent screen SHALL list only notes recorded on this watch, newest first within each section. Notes recorded on the iPhone SHALL never appear on the watch.

#### Scenario: Phone note
- GIVEN the person recorded a note on the iPhone
- WHEN they open Recent on the watch
- THEN that note is not listed

### Requirement: Sections and rows
Recent SHALL group notes into "Needs you · N", "Waiting · N" and "Done", in that order, hiding empty sections. Each row SHALL show the time the note was recorded and its length. Done rows SHALL also show the first line of the transcript; rows that need the person SHALL show a red reason line. Rows SHALL NOT be tappable. With no notes, Recent SHALL show "No notes yet".

| Note state | Section | Icon | Line under the time |
|---|---|---|---|
| Waiting to upload (offline, no token yet, retrying) | Waiting | gray clock | none |
| Uploading or being transcribed | Waiting | small spinner | none |
| Transcribed | Done | gray check | first line of the transcript, one line, cut with an ellipsis |
| Held: free notes used up | Needs you | red mark | "Unlock to transcribe" |
| Held: over fair use | Needs you | red mark | "Over fair use" |
| Stuck past the alert threshold | Needs you | red mark | "Waiting N min" under an hour, then "Waiting 1 hour" / "Waiting N hours" |
| Transcription failed for good | Needs you | red mark | "Couldn't transcribe" |
| Audio lost before it was uploaded | Needs you | red mark | "Audio lost" |

#### Scenario: Quick transcript
- GIVEN the watch is online
- WHEN the person records a short note and opens Recent a few seconds later
- THEN the note is under "Done" with the first line of what they said

#### Scenario: Empty transcript
- GIVEN the server returns an empty transcript for a silent note
- WHEN the note shows in Recent
- THEN its line reads "No words heard"

#### Scenario: Seeing a lost note
- GIVEN a note's audio was lost and the badge is red because of it
- WHEN the person opens Recent
- THEN the note stays listed with "Audio lost" but no longer turns the badge red

### Requirement: Notes age out
A note SHALL leave Recent 24 hours after its transcript arrives, and a failed or lost note 24 hours after the person first sees it in Recent. Notes that are waiting, held or stuck SHALL stay until they are done. Recent SHALL keep at most the 50 newest notes.

#### Scenario: Next day
- GIVEN a note was transcribed yesterday morning
- WHEN the person opens Recent the next afternoon
- THEN that note is no longer listed, and it remains in the iPhone's history

## Sending notes

### Requirement: Upload straight to Ramble's server
After every stop, the watch SHALL upload the note's audio straight to Ramble's server using its own token, over whatever connection it has (through the paired iPhone, known Wi-Fi, or cellular), without needing the iPhone app to be open. An upload SHALL carry on in the background after the wrist goes down, though watchOS may delay it. Each note SHALL be uploaded under its own ID, so a retried upload is never counted twice (see relay-api.md).

#### Scenario: iPhone left at home
- GIVEN the iPhone is at home and the watch is on Wi-Fi
- WHEN the person records a note
- THEN the note uploads and is transcribed without the iPhone

### Requirement: Retry until accepted
The watch SHALL keep every note that the server has not accepted and SHALL retry it on its own: while the app is open after 10 seconds, doubling up to every 5 minutes; whenever the app opens or comes back to the foreground; when a connection or a new token arrives; and in a background pass about every 10 minutes while notes are waiting, as often as watchOS allows. The watch SHALL never give up on a note or delete its audio because uploads keep failing.

#### Scenario: Offline for a day
- GIVEN the watch has been offline for a day with three notes waiting
- WHEN it gets a connection and the app runs
- THEN all three upload, and each is counted once

### Requirement: Read back status and transcript
The watch SHALL learn each uploaded note's status and transcript from the server by note ID, using only its own token: from the upload response when the transcript is ready quickly, otherwise every 10 seconds while the app is open, when the app opens, and in background passes.

#### Scenario: Long note
- GIVEN a 40-minute note was accepted but not yet transcribed
- WHEN the person opens the app later
- THEN the watch checks the note and moves it to "Done" if the transcript is ready

### Requirement: Keep audio until the transcript exists
The watch SHALL keep a note's audio until the server reports that its transcript is done, and until the iPhone confirms it has the audio, whichever is later, but no longer than 7 days after the transcript is done.

#### Scenario: Transcribed, iPhone away
- GIVEN a note is transcribed while the iPhone is out of range
- WHEN the iPhone comes back in range within 7 days and the watch app opens
- THEN the watch sends the audio to the iPhone and deletes it once the iPhone confirms

### Requirement: Held notes wait for unlock
When the server replies that the person is out of free notes, the watch SHALL keep the note and its audio, show it as "Unlock to transcribe", stop retrying it, and retry it automatically as soon as the iPhone reports that Ramble is unlocked. Notes held over fair use SHALL be handled the same way with their own message. A held note SHALL never be accepted and then dropped. See subscription.md.

#### Scenario: Purchase on the iPhone
- GIVEN two notes on the watch show "Unlock to transcribe"
- WHEN the person unlocks Ramble on their iPhone
- THEN the watch uploads both notes without the person opening the watch app, if the watch is awake to hear it, and otherwise the next time it opens
- AND the "Unlock" alert goes away

### Requirement: No token yet
Before the watch has a token, it SHALL record and keep notes locally, show "Set up" (or "No phone" when Ramble is not on the iPhone), and upload every waiting note once a token arrives from the iPhone. If the server rejects the token, the watch SHALL keep its notes, show "Set up", and wait for a new token.

#### Scenario: Watch app used before the phone app
- GIVEN Ramble was installed on both devices but never opened on the iPhone
- WHEN the person records three notes on the watch, then opens Ramble on the iPhone
- THEN the watch receives its token and uploads all three notes

### Requirement: Tell the iPhone right away
At each stop, the watch SHALL send the note's details (ID, when it was recorded, length) to the iPhone at once when it is in reach, so the iPhone can show the note and fetch its transcript. It SHALL also send the audio to the iPhone in the background, as a best effort, for playback in history.

#### Scenario: Note shows on the iPhone
- GIVEN the iPhone is nearby
- WHEN the person stops a note on the watch
- THEN the note appears in the iPhone's list within a few seconds, before its transcript

### Requirement: Resend audio on open and on request
Each time the watch app opens, it SHALL resend to the iPhone any audio the iPhone has not confirmed. When the iPhone asks for a note's audio while the watch app is open, the watch SHALL send it right away.

#### Scenario: Tapping "Audio on watch"
- GIVEN the watch app is open and the iPhone shows "Audio on watch" for a note
- WHEN the person taps that row on the iPhone
- THEN the watch sends that note's audio immediately

## Stuck-note alerts

### Requirement: One alert for stuck notes
The watch SHALL post one local notification when a note has gone 6 hours after it was recorded without being accepted and transcribed by the server. Held notes SHALL NOT count. The notification SHALL cover every note still waiting, as a count, never one per note, with the title "Still on your watch" and the body "1 note hasn't been transcribed yet. It's safe here and will keep trying." or "N notes haven't been transcribed yet. They're safe here and will keep trying."

#### Scenario: Phone at home all day
- GIVEN the watch has been offline for 7 hours with four waiting notes, one of them over 6 hours old
- WHEN the alert fires
- THEN one notification says "4 notes haven't been transcribed yet."

#### Scenario: Held notes only
- GIVEN five notes are held as "Unlock to transcribe" for 2 days
- WHEN the watch checks for stuck notes
- THEN no notification is posted

### Requirement: Alert limits
The watch SHALL post at most one stuck-note notification every 6 hours. A note SHALL only trigger a notification once, so a new one needs a newly stuck note. When no notes are waiting, any shown notification SHALL be removed. A note released from a hold SHALL count from when it was released.

#### Scenario: Everything goes through
- GIVEN a stuck-note notification is showing
- WHEN every waiting note is transcribed
- THEN the notification is removed

### Requirement: Alerts fire without the app
The watch SHOULD schedule a predicted stuck-note notification ahead of time so it fires even if the app does not run again, and SHOULD try to run a background pass about 5 minutes before it fires so that notes that went through in the meantime cancel it.

#### Scenario: Note uploaded in the background
- GIVEN a notification is scheduled for 3 PM for one waiting note
- WHEN a background pass at 2:55 PM uploads it and it is transcribed
- THEN the 3 PM notification is cancelled

### Requirement: Notification permission
The watch SHALL ask for notification permission only while the app is open and at least one note exists, never at first launch, and only once.

#### Scenario: First launch
- GIVEN the person opens Ramble on the watch for the first time
- WHEN the home screen appears
- THEN no notification prompt shows

### Requirement: Fast alerts for testing
When the iPhone's debug setting for fast delivery alerts is on, the watch SHALL use 60 seconds for both the stuck threshold and the cooldown.

#### Scenario: Debug test
- GIVEN fast alerts are on and the watch is offline
- WHEN a note waits for 60 seconds
- THEN the stuck-note notification fires

## Siri and shortcuts

### Requirement: Watch shortcuts
The watch SHALL offer three shortcuts that open the app and act like the button. "Start a Ramble" ("Start a Ramble", "Start recording with Ramble") starts silently with the start haptic. "Stop my Ramble" ("Stop my Ramble", "Stop recording with Ramble") stops and saves and says "Saved.", or says "No recording in progress." when nothing is recording. "Ramble" ("Ramble", "Toggle Ramble") starts or stops silently, with the haptic telling which. A failed start SHALL play the failure haptic and say "Allow microphone in Settings." when the microphone is off, or "Couldn't start recording." otherwise.

#### Scenario: Start by voice
- GIVEN nothing is recording
- WHEN the person says "Start a Ramble"
- THEN Ramble opens and starts recording with the start haptic and no spoken reply

#### Scenario: Stop by voice
- GIVEN the watch is recording
- WHEN the person says "Stop my Ramble"
- THEN the note is saved with the same check and haptic as a button stop, and Siri says "Saved."
