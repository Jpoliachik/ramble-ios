# Watch

## Purpose
What the person experiences on Apple Watch: recording a note, the home screen and its states, the short list of recent notes, and how the watch sends each note straight to Ramble's server and says when one is stuck. The watch works without the iPhone nearby; the iPhone holds the full history (phone.md).

## Home screen

### Requirement: One button, one bar
The home screen SHALL show one record button centered on the full screen and one bar along the bottom edge, with nothing above the button and the button never moving when the bar changes. The button SHALL be the only control that starts and stops recording on this screen.

#### Scenario: At rest
- GIVEN the watch app is open and nothing is recording
- WHEN the person looks at the watch
- THEN the button shows an amber ring with a filled amber disc
- AND the bar shows the history button at the right, and an alert at the left only if one is active

#### Scenario: VoiceOver order
- GIVEN VoiceOver is on and an alert is active
- WHEN the person moves through the home screen
- THEN it reads "Record" (or "Stop recording"), then the alert's detail title with the hint "Double tap for help" when it has a detail screen, then "Recent"

### Requirement: Words rule for the bar
A bar alert SHALL be one icon plus at most 8 characters, counting spaces, ending at least 12pt before the history button on every watch size, and SHALL never shrink its font or wrap. Only one alert SHALL show at a time, and while recording it SHALL show only its icon.

#### Scenario: Words drop while recording
- GIVEN the "No phone" alert is active
- WHEN recording starts
- THEN the bar shows only the iPhone icon, and the words come back when recording stops

### Requirement: Bar alerts and their order
The watch SHALL pick at most one bar alert in this order: "Mic off", "Mic busy", "No phone", "Set up", "Unlock", "Limit". The two microphone alerts SHALL be red, because nothing can be recorded; the rest SHALL be gray, because recording still works.

| Alert | When | Detail title | Detail text |
|---|---|---|---|
| "Mic off" | Microphone permission is off, checked at launch and on every return to the foreground | "Microphone is off" | "Ramble can't hear you, so nothing gets recorded." / "On your watch, open Settings, then Privacy & Security, then Microphone, and turn on Ramble." |
| "Mic busy" | For 3 seconds after a start fails for any reason other than permission | "Microphone is busy" (read by VoiceOver; no detail screen, since tapping again is the fix) | none |
| "No phone" | The paired iPhone does not have Ramble | "Ramble isn't on your iPhone" | "Your notes are safe on this watch, but they can't reach your agent yet." / "Install Ramble on your iPhone and open it once. Waiting notes will send on their own." |
| "Set up" | Ramble is on the iPhone, but the watch is not connected to it yet, or the server no longer accepts the watch's connection | "Open Ramble on your iPhone" | "Your notes are safe on this watch, but they can't send yet." / "Open Ramble on your iPhone once. Waiting notes will send on their own." |
| "Unlock" | A note is held because the free notes are used up | "Unlock to transcribe" | "You've used your free notes. Your notes are safe on this watch." / "Unlock Ramble on your iPhone and they'll transcribe on their own." |
| "Limit" | A note is held over fair use | "Over fair use" | "Your notes are safe on this watch." / "This note will transcribe on Dec 1." (the date is the reset date the server gives; subscription.md) |

#### Scenario: Highest alert wins
- GIVEN microphone permission is off and the paired iPhone doesn't have Ramble
- WHEN the home screen shows
- THEN only "Mic off" shows, in red

#### Scenario: Gray alert with a detail screen
- GIVEN a note is held over fair use and nothing else is wrong
- WHEN the person taps "Limit", shown in gray with a chevron
- THEN a detail screen opens with the icon and title, what happened, and when it resolves

### Requirement: First launch hint
Until the first note is ever saved on this watch, a soft amber ring SHALL breathe out from the button every 2.2 seconds, unless the microphone is off or Reduce Motion is on. Once a note has been saved, the ring SHALL never return, even after every note has left Recent.

#### Scenario: First note
- GIVEN the watch has never saved a note
- WHEN the person records and stops their first note
- THEN the breathing ring stops for good

### Requirement: History badge
The history button SHALL carry at most one mark, highest first: a red dot if any note needs the person (held, failed, refused, stuck, or lost and not yet opened in Recent); a spinning ring while any note is uploading or being transcribed; a still gray dot if any note is waiting to upload; otherwise nothing. The history button SHALL be hidden while recording.

#### Scenario: Reduce Motion
- GIVEN Reduce Motion is on and a note is uploading
- WHEN the home screen shows
- THEN a still gray dot stands in for the spinning ring

## Recording

### Requirement: Instant start
A tap on the button, or a double tap on watches that support it, SHALL start recording at once, without waiting on the iPhone, the network, or setup, and SHALL play the start haptic. Nothing the iPhone does SHALL stop a watch recording.

#### Scenario: Start with the phone away
- GIVEN the iPhone is out of range and the watch is offline
- WHEN the person taps the button
- THEN recording starts and the start haptic plays

### Requirement: While recording
While recording, the disc SHALL give way to three amber level bars that follow the person's voice, and the bar SHALL show the elapsed time in amber serif digits, read by VoiceOver as, for example, "Recording, 1 minute, 4 seconds". The recording SHALL keep running when the wrist goes down, the screen sleeps, or the app goes to the background.

#### Scenario: Wrist down mid-note
- GIVEN the person is recording
- WHEN they lower their wrist for two minutes and raise it again
- THEN the recording is still running and the timer shows the full elapsed time

### Requirement: Stop and save
Every stop SHALL save the note on the watch at once, play the success haptic, and draw a check inside the disc that is gone by 0.8 seconds (shown without drawing under Reduce Motion). A stop SHALL look and feel the same whatever caused it: the button, double tap, Siri, the 60-minute cap, or a call, Siri or alarm taking the microphone. A tap during the check SHALL start another recording at once.

#### Scenario: A call takes the microphone
- GIVEN the person is recording
- WHEN a phone call takes the microphone
- THEN everything said so far is saved as a note, with the same haptic and check

### Requirement: 60-minute cap
From 55:00 the timer SHALL count down the time left with a minus sign (for example "−4:59"), and one notification haptic SHALL play at 55:00. At 60:00 the recording SHALL stop like any other stop. The server's length limit is in transcription.md.

#### Scenario: Nearing the cap
- GIVEN a recording reaches 55:00
- WHEN the timer updates
- THEN one haptic plays and the timer reads "−5:00", counting down

#### Scenario: Hard stop
- GIVEN a recording reaches 60:00
- WHEN the cap is hit
- THEN the note is saved with the success haptic and check, and no second note starts

### Requirement: Recording format
Recordings SHALL be mono AAC at 16 kHz and at most 32 kbps, so a 60-minute note fits the upload limit (transcription.md).

#### Scenario: Full hour
- GIVEN a recording runs to 60:00
- WHEN it is saved
- THEN the file is under 15 MB

### Requirement: Microphone permission and busy mic
The first tap SHALL show the system microphone prompt with the text "Ramble records what you say on your watch and sends it to your agent." and SHALL start recording if the person allows it. While permission is off, the button SHALL look dimmed, and a tap SHALL play the failure haptic, shake "Mic off" sideways (no shake under Reduce Motion), and not record. When a start fails for any other reason, the watch SHALL play the failure haptic and show "Mic busy" for 3 seconds.

#### Scenario: Permission denied
- GIVEN microphone permission is off
- WHEN the person taps the button
- THEN the failure haptic plays, "Mic off" shakes, and nothing records

#### Scenario: Another app has the mic
- GIVEN another app holds the microphone
- WHEN the person taps the button
- THEN the failure haptic plays and "Mic busy" shows for 3 seconds

## Recent notes on the watch

### Requirement: Only this watch's notes
Recent SHALL list only notes recorded on this watch. Notes recorded on the iPhone SHALL never appear on the watch.

#### Scenario: Phone note
- GIVEN the person recorded a note on the iPhone
- WHEN they open Recent on the watch
- THEN that note is not listed

### Requirement: Sections and rows
Recent SHALL group notes, newest first, into "Needs you · N", "Waiting · N" and "Done", hiding empty sections. Each row SHALL show when the note was recorded and its length, plus the line below. Rows SHALL NOT be tappable. With no notes, Recent SHALL show "No notes yet".

| Note | Section | Icon | Line below |
|---|---|---|---|
| Waiting to upload | Waiting | gray clock | none |
| Uploading or being transcribed | Waiting | small spinner | none |
| Transcribed | Done | gray check | first line of the transcript, cut with an ellipsis |
| Silent | Done | gray check | "No speech detected" |
| Held: free notes used up | Needs you | red mark | "Unlock to transcribe" |
| Held: fair use | Needs you | red mark | "Over fair use" |
| Not yet accepted 6 hours after recording | Needs you | red mark | "Waiting 6 hours", "Waiting 7 hours", … |
| Transcription failed for good | Needs you | red mark | "Couldn't transcribe" |
| Audio lost before the server accepted it | Needs you | red mark | "Audio lost" |
| Refused as over the length limit | Needs you | red mark | "Too long to transcribe" |
| Refused for good for another reason | Needs you | red mark | "Couldn't send" |

#### Scenario: A held note needs the person
- GIVEN the only note on the watch is held because the free notes are used up
- WHEN the person opens Recent
- THEN it is listed under "Needs you · 1" with a red mark and "Unlock to transcribe"

### Requirement: Notes leave Recent
A transcribed or silent note SHALL leave Recent 24 hours after its transcript arrives; a failed, refused or lost note SHALL leave 24 hours after the person first sees it. Notes that are waiting, held or stuck SHALL stay until they are done. When Recent passes 50 notes, only done, failed, refused or lost notes SHALL be dropped, oldest first.

#### Scenario: Next day
- GIVEN a note was transcribed yesterday morning
- WHEN the person opens Recent the next afternoon
- THEN the note is gone from the watch and remains in the iPhone's history

## Sending notes

### Requirement: Upload straight to Ramble's server
After every stop, the watch SHALL upload the note straight to Ramble's server over any connection it has (through the iPhone, Wi-Fi, or cellular), without needing the iPhone app open. An upload SHOULD start within 1 minute of the stop while the app is open; with the app in the background, watchOS decides when. Upload rules are in relay-api.md.

#### Scenario: iPhone left at home
- GIVEN the iPhone is at home and the watch is on Wi-Fi
- WHEN the person records a note
- THEN the note uploads and is transcribed without the iPhone

### Requirement: Retry until accepted
The watch SHALL keep every note the server has not accepted and SHALL never give up on it or delete its audio because uploads fail. It SHALL retry 10 seconds after a failure while the app is open, doubling to every 5 minutes, and whenever the app opens, a connection returns or the watch is set up. It SHOULD also retry about every 10 minutes in the background, as often as watchOS allows. When the server says to wait (rate limit), the watch SHALL wait that long.

#### Scenario: Answer lost in transit
- GIVEN the server accepted a note but the watch never got the answer
- WHEN the watch tries again weeks later
- THEN it learns the note was already accepted, and the note is not counted or transcribed twice

### Requirement: Refused for good
When the server refuses a note's audio for good (relay-api.md), the watch SHALL stop retrying it, keep the audio until the iPhone has it, show "Too long to transcribe" or "Couldn't send", and never raise a stuck alert for it.

#### Scenario: Damaged file
- GIVEN the server refuses a note's audio as unreadable
- WHEN the watch gets the answer
- THEN the note shows "Couldn't send" under Needs you and the watch stops retrying it

### Requirement: Status and transcript
The watch SHALL learn each accepted note's status and transcript from the server: from the upload answer when the transcript is ready within 8 seconds (relay-api.md), otherwise every 10 seconds while the app is open, when it opens, and in background passes.

#### Scenario: Long note
- GIVEN a 40-minute note was accepted but not yet transcribed
- WHEN the person opens the app later
- THEN the note moves to "Done" with its first line once the transcript is ready

### Requirement: Keep audio until it is safe
The watch SHALL keep a note's audio until both the transcript is done (or transcription failed for good, or the server refused the note) and the iPhone has confirmed it has the audio. If the iPhone never confirms, the audio SHALL be deleted 30 days after the transcript is done.

#### Scenario: Transcribed, iPhone away
- GIVEN a note is transcribed while the iPhone is away
- WHEN the iPhone comes back within 30 days and the watch app opens
- THEN the watch sends the audio to the iPhone and deletes it once the iPhone confirms

### Requirement: Held for unlock
When the server holds a note because the free notes are used up, the watch SHALL keep the note and its audio, show "Unlock to transcribe", and stop retrying it. It SHOULD upload held notes, oldest first, as soon as the iPhone says Ramble is unlocked or connects the watch again, even with the watch app closed; it SHALL do so at the latest the next time the app opens and the server reports the unlock. The money side is in subscription.md.

#### Scenario: Purchase on the iPhone
- GIVEN two notes on the watch show "Unlock to transcribe"
- WHEN the person unlocks Ramble on their iPhone and the watch is in reach
- THEN the watch uploads both notes, oldest first, usually without the watch app being opened, and at the latest when it next opens
- AND the "Unlock" alert goes away

### Requirement: Held over fair use
When the server holds a note over fair use, the watch SHALL keep the note and its audio, show "Over fair use", and retry it at the reset time the server gave and on every app open after it.

#### Scenario: Month resets
- GIVEN a note has been held over fair use since November 28
- WHEN the person opens the watch app on December 1
- THEN the note uploads and is transcribed

### Requirement: Not set up yet
Until the iPhone has connected the watch, the watch SHALL record and keep notes, show "Set up" (or "No phone"), and upload every waiting note once connected. When the server stops accepting the watch's connection, the watch SHALL keep its notes, show "Set up", and wait for the iPhone to connect it again.

#### Scenario: Watch app used first
- GIVEN Ramble was installed on both devices but never opened on the iPhone
- WHEN the person records three notes on the watch, then opens Ramble on the iPhone
- THEN the watch is connected and uploads all three notes

### Requirement: Connection replaced
When the iPhone connects the watch again, the watch's previous connection SHALL stop uploading (relay-api.md). The watch SHALL keep reading notes the previous connection already uploaded until each is done, upload every note not yet accepted under the current connection, and retry its held notes.

#### Scenario: iPhone reinstalled
- GIVEN the watch has one note accepted but not transcribed and one note waiting
- WHEN Ramble is reinstalled on the iPhone and connects the watch again
- THEN the accepted note still moves to "Done", and the waiting note uploads under the current connection

### Requirement: Tell the iPhone right away
At each stop, when the iPhone is in reach, the watch SHALL send it the note's ID, recorded time and length at once; the note SHOULD appear in the iPhone's list within 5 seconds when both are awake. The watch SHALL also tell the iPhone whenever a note becomes held (for unlock or fair use) or is released, and SHALL send the audio in the background, as a best effort, for playback.

#### Scenario: Note shows on the iPhone
- GIVEN the iPhone is nearby
- WHEN the person stops a note on the watch
- THEN the note appears in the iPhone's list before its transcript

### Requirement: Resend audio on open and on request
Each time the watch app opens, it SHALL resend any audio the iPhone has not confirmed. When the iPhone asks for a note's audio while the watch app is open, the watch SHALL send it right away.

#### Scenario: Tapping "Audio on watch"
- GIVEN the watch app is open and the iPhone shows "Audio on watch" for a note
- WHEN the person taps that row on the iPhone
- THEN the watch sends that note's audio immediately

## Stuck-note alerts

### Requirement: One alert for stuck notes
The watch SHALL post one notification titled "Still on your watch" when one of its notes has gone 6 hours after recording without the server accepting it. Notes the server accepted, held notes and refused notes SHALL never count. The notification SHALL count every note that is not yet accepted and not held or refused:

| Count | Body |
|---|---|
| 1 | "1 note hasn't reached Ramble yet. It's safe here and will send on its own." |
| N | "N notes haven't reached Ramble yet. They're safe here and will send on their own." |

#### Scenario: Phone at home all day
- GIVEN the watch has been offline for 7 hours with four notes not yet accepted, one over 6 hours old
- WHEN the alert fires
- THEN one notification says "4 notes haven't reached Ramble yet."

#### Scenario: Held notes only
- GIVEN five notes have been held as "Unlock to transcribe" for 2 days
- WHEN the watch checks for stuck notes
- THEN no notification is posted

### Requirement: Alert limits
The watch SHALL post at most one stuck-note notification every 6 hours, and each note SHALL trigger one at most once. When no notes are waiting to be accepted, a shown notification SHALL be removed. A note released from a hold SHALL count its 6 hours from the release. The notification SHALL appear on time even if the watch app does not run, and SHOULD NOT appear for notes the server accepted before it was due, unless the watch could not learn of the acceptance in time. The watch SHALL ask for notification permission once, only while the app is open and at least one note exists.

#### Scenario: Note uploaded in the background
- GIVEN a notification is due at 3 PM for one waiting note
- WHEN that note is accepted at 2:55 PM in the background
- THEN no notification appears at 3 PM

#### Scenario: First launch
- GIVEN the person opens Ramble on the watch for the first time
- WHEN the home screen appears
- THEN no notification prompt shows

## Siri and shortcuts

### Requirement: Watch shortcuts
"Start a Ramble" and "Start recording with Ramble" SHALL open the app and start recording silently with the start haptic; if already recording, nothing changes. A failed start SHALL play the failure haptic and say "Allow microphone in Settings." when the microphone is off, or "Couldn't start recording." otherwise. "Stop my Ramble" and "Stop recording with Ramble" SHALL stop and save like the button and say "Saved.", or say "No recording in progress." when nothing is recording. "Ramble" and "Toggle Ramble" SHALL start or stop silently, with the haptic telling which.

#### Scenario: Start by voice
- GIVEN nothing is recording
- WHEN the person says "Start a Ramble"
- THEN Ramble opens and records, with the start haptic and no spoken reply

#### Scenario: Stop by voice
- GIVEN the watch is recording
- WHEN the person says "Stop my Ramble"
- THEN the note is saved with the same check and haptic as a button stop, and Siri says "Saved."
