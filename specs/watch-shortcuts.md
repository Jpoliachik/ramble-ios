# Watch shortcuts

## Purpose
The ways to start a recording on Apple Watch without tapping the record button on Ramble's home screen: Siri, the Ramble control, and the Ramble complication. Recording itself, and what a stop saves, are in [watch.md](watch.md).

## Siri and the control

### Requirement: Watch shortcuts
The watch SHALL offer one action, "Ramble", that works like the record button: it starts recording when nothing is recording and stops and saves like the button when something is. Siri phrases "Ramble", "Toggle Ramble", "Start a Ramble", "Start recording with Ramble", "Stop my Ramble" and "Stop recording with Ramble" all run it. It SHALL bring Ramble to the front before it starts, so a recording started from Siri or the control keeps going and shows its timer. It SHALL be silent both ways, with the start or stop haptic telling which. A failed start SHALL play the failure haptic and say "Allow microphone in Settings." when the microphone is off, or "Couldn't start recording." otherwise.

### Requirement: Ramble control
On watchOS 26 and later, the watch app SHALL offer a "Ramble" control that runs the same action. A person can assign it to the Apple Watch Ultra Action button, or add it to Control Center or the Smart Stack. It runs on the watch, not the iPhone. Shortcuts built on the iPhone run the iPhone app's actions, so they are not a way to record on the watch.

#### Scenario: Start from the Action button
- GIVEN nothing is recording and the Action button is set to the Ramble control
- WHEN the person presses the Action button
- THEN Ramble opens and records, with the start haptic and no spoken reply, and keeps recording

#### Scenario: Stop from the same action
- GIVEN the watch is recording
- WHEN the person presses the Action button again, or says "Stop my Ramble"
- THEN the note is saved with the same check and haptic as a button stop, and nothing is spoken

## Complication

### Requirement: Ramble complication
On every watchOS Ramble supports, the watch app SHALL offer a "Ramble" complication for watch faces and the Smart Stack, in four sizes: circular and corner show the record button at rest (an amber ring around an amber disc), the corner one with "Ramble" along its curve; rectangular shows the same button beside "Ramble" and "Tap to record"; inline shows a waveform and "Ramble". It SHALL show no note counts or status. On a tinted face it SHALL take the face's tint instead of amber.

#### Scenario: Add it to a face
- GIVEN Ramble is installed on the watch
- WHEN the person edits a watch face and picks a complication slot
- THEN "Ramble" is offered in the sizes that slot takes

### Requirement: Tap the complication to record
Tapping the complication SHALL open Ramble on its home screen and start recording, exactly as a tap on the record button does: the same start haptic, timer and failure handling, with nothing spoken. It SHALL only ever start: when a recording is already running, the tap opens Ramble to that recording and leaves it running. If another screen of Ramble was open, the tap SHALL return to the home screen first.

#### Scenario: Start from the watch face
- GIVEN nothing is recording and the Ramble complication is on the current face
- WHEN the person taps it
- THEN Ramble opens on its home screen and records, with the start haptic and the timer

#### Scenario: Already recording
- GIVEN the watch is recording and the person has gone back to the watch face
- WHEN the person taps the Ramble complication
- THEN Ramble opens showing the running recording's timer, and the recording keeps going

#### Scenario: Microphone off
- GIVEN Ramble's microphone access is off
- WHEN the person taps the complication
- THEN Ramble opens, plays the failure haptic and shakes "Mic off", as for a tap on the button, and nothing records
