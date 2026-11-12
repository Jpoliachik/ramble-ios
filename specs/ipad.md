# iPad

## Purpose
How the iPhone app differs when it runs on iPad. An Apple Watch pairs only with an iPhone, so on iPad Ramble is a phone-style recorder with no watch. Everything not listed here behaves as [phone.md](phone.md) says.

## Requirements

### Requirement: The app names the iPad
Wherever the app's own words name the device it runs on ("Record on iPhone", "via iPhone", "Recorded on iPhone", "Waiting for this iPhone to be unlocked.", "Notes stay on your iPhone until you connect one.", the webhook and history lines in "Your data", and the privacy wording in [delivery.md](delivery.md)), it SHALL say "iPad" on an iPad. Lines that say "watch and iPhone" SHALL name only the iPad ("Recordings from your iPad go to Ramble's server…", "Unlimited notes from your iPad."). The usage stats line keeps "your watch or iPad". The website and llms files keep "iPhone".

#### Scenario: Recording label
- GIVEN Ramble is open on an iPad
- WHEN the person starts recording with the built-in microphone
- THEN the recording screen reads "via iPad" and the note's activity log reads "Recorded on iPad"

### Requirement: No watch setup on iPad
On an iPad, onboarding SHALL open on a single intro screen, "Let it go.", with no story bar and the same "Get started" button and consent line, instead of the three beats. "Get started" SHALL go straight to connecting an agent, skipping "Where should notes go?" (a webhook is set up in Settings) and the watch step, with no progress bar or Back. Once the agent connects, or the person chooses "Set up later", onboarding finishes and shows "You're all set" on Home. Settings SHALL NOT show the "Watch" group, Home SHALL NOT show "Or record here" above the record button, and Home with no notes SHALL show only the "TRY SAYING" ideas, without the watch drawing.

#### Scenario: Onboarding on iPad
- GIVEN Ramble is opened for the first time on an iPad
- WHEN the person taps "Get started", then "Set up later" on "Connect your agent."
- THEN onboarding closes and Home shows "You're all set", with no "Now, put it on your watch." or "No watch? No problem."

### Requirement: Readable width
On a screen wider than about 760 points, the notes list, the Home header and status line, and the note screen SHALL keep their content about 680 points wide, centered. Sheets (onboarding, Settings, the agent screen, the unlock sheet) keep the system's iPad sheet size.

#### Scenario: Landscape iPad
- GIVEN an iPad in landscape with notes on Home
- WHEN the person looks at Home
- THEN the note rows and the "Ramble" header sit in a centered column, not edge to edge
