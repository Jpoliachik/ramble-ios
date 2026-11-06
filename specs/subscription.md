# Free notes and unlock

## Purpose
How Ramble is paid for: 25 free notes, then a one-time $14.99 unlock with no subscription. Covers counting free notes, what happens to notes when they run out, buying and restoring the unlock, how every device learns about it, fair use, people who paid under the old pricing, and what Ramble says about price. The upload endpoint and its status codes are in relay-api.md; what a held note looks like on each screen is in watch.md and phone.md.

## Free notes

### Requirement: 25 free notes per inbox
Ramble SHALL transcribe the first 25 notes from an inbox for free, counted on the server by distinct note, at the moment an upload is accepted (the audio is safely stored). Notes from the watch and the iPhone of one person share one count.

#### Scenario: A note uses one free note
- GIVEN an inbox that is not unlocked and has 25 free notes left
- WHEN the watch uploads a note and the server accepts it
- THEN the inbox has 24 free notes left

#### Scenario: A retried upload never counts twice
- GIVEN a note that was accepted, but the device never saw the reply
- WHEN the device uploads the same note again
- THEN the server treats it as the same note
- AND the free count does not change

#### Scenario: Watch and iPhone race for the last free note
- GIVEN an inbox with 1 free note left
- WHEN the watch and the iPhone each upload a different note at the same moment
- THEN exactly one note is accepted
- AND the other is held as "Unlock to transcribe"

### Requirement: Free note refunded on permanent failure
The server SHALL give back a free note when that note's transcription permanently fails, so a failed note never costs the person anything.

#### Scenario: Every provider fails for good
- GIVEN an inbox with 10 free notes left
- WHEN a note is accepted (9 left) and its transcription permanently fails as described in transcription.md
- THEN the inbox has 10 free notes left again

#### Scenario: A silent note still counts
- GIVEN a note that transcribes successfully but contains no speech
- WHEN its transcript is ready
- THEN the free note stays used

### Requirement: Remaining count is shown
The iPhone app SHALL show how many free notes are left, using the count the server last reported. It SHALL appear in Settings at all times before unlock as "N of 25 free notes left", and on the notes list as "N free notes left" once 5 or fewer remain. The watch SHALL NOT show the count.

#### Scenario: Count in Settings
- GIVEN an inbox with 18 free notes left
- WHEN the person opens Settings
- THEN they see "18 of 25 free notes left" with an "Unlock" button

#### Scenario: Running low
- GIVEN an inbox with 3 free notes left
- WHEN the person opens the notes list
- THEN a line reads "3 free notes left" and tapping it opens the unlock sheet

#### Scenario: Unlocked
- GIVEN an inbox that is unlocked
- WHEN the person opens Settings or the notes list
- THEN no free count appears, and Settings shows "Unlocked"

### Requirement: Reinstall starts a new count
A new inbox SHALL start with 25 free notes. Reinstalling the iPhone app creates a new inbox, so the count starts again at 25. "Delete everything" keeps the same inbox and SHALL NOT change the count or the unlock.

#### Scenario: Reinstall
- GIVEN a person with 0 free notes left and no purchase
- WHEN they delete and reinstall Ramble on the iPhone
- THEN the new inbox has 25 free notes left

## Running out

### Requirement: Notes over the free limit are held, never dropped
When an inbox with no free notes left and no unlock uploads a note, the server SHALL refuse it without storing or counting it, and the recording device SHALL keep the audio and show the note as "Unlock to transcribe". A note SHALL NEVER be accepted and then dropped for payment reasons.

#### Scenario: 26th note on the watch
- GIVEN an inbox with 0 free notes left and no unlock
- WHEN the watch uploads a new note
- THEN the server refuses it as payment required (relay-api.md)
- AND the watch keeps the audio and shows the note as "Unlock to transcribe"
- AND the watch tells the person to "Unlock on your iPhone"

#### Scenario: 26th note on the iPhone
- GIVEN an inbox with 0 free notes left and no unlock
- WHEN the iPhone uploads a new note
- THEN the note row shows "Unlock to transcribe"
- AND tapping it opens the unlock sheet

### Requirement: Held notes wait quietly
A note held for unlock SHALL NOT be retried on a timer and SHALL NOT trigger stuck-note alerts on the watch or the iPhone. It SHALL be kept on the recording device for as long as it takes.

#### Scenario: No alert after days
- GIVEN a note held as "Unlock to transcribe" for 3 days
- WHEN the stuck-note checks run
- THEN no alert is shown for that note

### Requirement: Held notes upload after unlock
When an inbox becomes unlocked, every device SHALL upload its held notes automatically, oldest first, with no action from the person.

#### Scenario: Unlock on the iPhone releases watch notes
- GIVEN the watch holds 4 notes as "Unlock to transcribe"
- WHEN the person buys the unlock on the iPhone
- THEN the iPhone tells the watch the inbox is unlocked
- AND the watch uploads the 4 notes, and they transcribe as usual

#### Scenario: Watch was away during the purchase
- GIVEN the watch was out of range when the person bought the unlock
- WHEN the watch next hears from the iPhone, or the Ramble watch app is opened
- THEN the watch tries its held notes again
- AND if the server still refuses them, they stay held

## The unlock purchase

### Requirement: One-time unlock, no subscription
Ramble SHALL sell one non-consumable in-app purchase, "Unlock Ramble", that transcribes every note from the person's inbox for good, within fair use. There SHALL be no subscription for sale.

#### Scenario: What the purchase buys
- GIVEN a person who bought the unlock
- WHEN they record on the watch or the iPhone at any later time
- THEN the notes transcribe with no further charge, within fair use

### Requirement: Where the unlock is offered
The iPhone app SHALL offer the unlock sheet from Settings, from any note marked "Unlock to transcribe", and from the "free notes left" line on the notes list. It SHALL NOT be shown as a gate in onboarding, and the watch SHALL NOT offer a purchase.

#### Scenario: From a held note
- GIVEN a note marked "Unlock to transcribe"
- WHEN the person taps it
- THEN the unlock sheet opens

### Requirement: Unlock sheet
The unlock sheet SHALL show the price exactly as the App Store reports it for the person's storefront, the words "One-time purchase. No subscription.", a fair-use note linking to the Terms of Use, a "Restore Purchases" button, and links to the Terms of Use and Privacy Policy. It SHALL NOT show a hardcoded price.

#### Scenario: Price from the store
- GIVEN a person in a storefront where the unlock costs €14,99
- WHEN they open the unlock sheet
- THEN the button reads "Unlock for €14,99"

#### Scenario: Store unreachable
- GIVEN the App Store price cannot be loaded
- WHEN the person opens the unlock sheet
- THEN the button reads "Unlock" and is disabled
- AND a line reads "Can't reach the App Store. Try again in a moment."

### Requirement: Purchase outcomes
The app SHALL handle every purchase outcome without losing a held note, and SHALL show the person what happened.

#### Scenario: Success
- GIVEN a person on the unlock sheet
- WHEN the purchase completes and the server confirms it
- THEN the sheet shows "Unlocked" and closes
- AND held notes upload automatically

#### Scenario: Cancelled
- WHEN the person cancels the App Store sheet
- THEN the unlock sheet stays open with no error shown

#### Scenario: Failed
- WHEN the App Store reports the purchase failed
- THEN the sheet shows "Purchase didn't go through. Try again."
- AND held notes stay held

#### Scenario: Pending or Ask to Buy
- GIVEN a child account that needs approval, or a payment that is pending
- WHEN the purchase is submitted
- THEN the sheet shows "Waiting for approval. Your notes are kept and will transcribe once it's approved."
- AND when approval arrives later, even with the app closed, the app confirms it with the server on next launch and held notes upload

#### Scenario: Paid, but the server can't be reached
- GIVEN the App Store purchase succeeded
- WHEN the app cannot confirm it with the server
- THEN the sheet shows "Purchase complete. Finishing setup. Your notes will transcribe shortly."
- AND the app retries confirming each time it opens or goes online until it succeeds

### Requirement: Restore Purchases
"Restore Purchases" SHALL be available in Settings and on the unlock sheet. It SHALL find the person's unlock (or old-pricing purchase, see below) for their Apple ID and confirm it with the server for the current inbox.

#### Scenario: Restore on a new iPhone
- GIVEN a person who bought the unlock on their old iPhone
- WHEN they install Ramble on a new iPhone and tap "Restore Purchases"
- THEN the new inbox is unlocked and Settings shows "Unlocked"

#### Scenario: Restored without asking
- GIVEN a person reinstalls Ramble while signed in with the Apple ID that bought the unlock
- WHEN the app first launches
- THEN the app confirms the purchase with the server on its own and the inbox is unlocked without tapping anything

#### Scenario: Nothing to restore
- GIVEN an Apple ID that never bought Ramble
- WHEN the person taps "Restore Purchases"
- THEN the app shows "No purchase found for this Apple ID."

## Entitlement

### Requirement: The server decides
The unlock SHALL live on the server, attached to the inbox. The iPhone SHALL send the App Store's signed purchase record once per inbox; the server verifies it and marks the inbox unlocked. Devices SHALL NOT decide on their own that notes may be transcribed.

#### Scenario: Forged purchase
- GIVEN a purchase record that is not signed by a chain leading to Apple's root certificate
- WHEN it is sent to the server
- THEN the server rejects it and the inbox stays locked

#### Scenario: Wrong app or product
- GIVEN a validly signed record for a different app or a different product
- WHEN it is sent to the server
- THEN the server rejects it

### Requirement: Other devices learn from the iPhone and the server
The watch SHALL learn about an unlock from the iPhone, and SHALL treat the server's reply to each upload as the final word. Uploading from the watch needs no purchase record on the watch.

#### Scenario: Unlocked inbox, watch never told
- GIVEN an inbox that is unlocked, and a watch that has not yet heard about it
- WHEN the watch uploads a note
- THEN the server accepts it, because the unlock belongs to the inbox

### Requirement: Purchase bound to inboxes, at most 5
Each purchase SHALL be tagged with the inbox it was bought from, and one purchase SHALL unlock at most 5 inboxes. Only inboxes that uploaded a note in the last 90 days count toward the 5.

#### Scenario: Sixth iPhone
- GIVEN a purchase already unlocking 5 inboxes active in the last 90 days
- WHEN the person restores it on a sixth inbox
- THEN the server refuses, and the app shows "This purchase is already in use on 5 iPhones. Remove Ramble from one you no longer use, or try again later."
- AND the new inbox keeps its free notes

#### Scenario: Old inbox ages out
- GIVEN one of the 5 inboxes has not uploaded in 90 days
- WHEN the person restores on a new iPhone
- THEN the new inbox is unlocked

### Requirement: Refunds remove the unlock
When Apple refunds or revokes a purchase, the server SHALL remove the unlock from every inbox it unlocked within 24 hours, and SHALL reject that purchase record from then on. Notes already accepted SHALL still be transcribed.

#### Scenario: Refunded after use
- GIVEN an unlocked inbox that has used all 25 free notes
- WHEN the person gets a refund from Apple
- THEN later uploads are held as "Unlock to transcribe"
- AND notes accepted before the refund still arrive

### Requirement: Test purchases never unlock production
The production server SHALL reject purchase records from the App Store sandbox and from Xcode testing, and SHALL accept no developer bypass key. A separate test server SHALL accept sandbox records.

#### Scenario: Sandbox record in production
- GIVEN a purchase made with a sandbox account
- WHEN it is sent to the production server
- THEN the server rejects it and the inbox stays locked

## Fair use

### Requirement: Monthly fair-use allowance
An unlocked inbox SHALL have a fair-use allowance of 100 hours of transcribed audio per purchase per calendar month (UTC), and 60 hours per recording device per calendar month. Duration SHALL be measured by the server from the transcription result, never taken from the device. Free notes are not subject to fair use.

#### Scenario: Shared purchase across devices
- GIVEN one purchase used by a watch and an iPhone
- WHEN together they transcribe 100 hours in November
- THEN further notes that month are held, even if neither device reached 60 hours

#### Scenario: The note that crosses the line
- GIVEN 99.5 hours used this month
- WHEN a 60-minute note is accepted
- THEN it transcribes in full
- AND only the uploads after it are held

### Requirement: Over fair use, notes are held
When an allowance is used up, uploads SHALL be refused without counting, the device SHALL keep the audio, and the note SHALL show "Over fair use. This note will transcribe on Dec 1." with the date the allowance resets. Held notes SHALL upload automatically after the reset, and SHALL NOT trigger stuck-note alerts.

#### Scenario: Reset releases held notes
- GIVEN 3 notes held for fair use in November
- WHEN December 1 (UTC) arrives and a device next opens or syncs
- THEN the 3 notes upload and transcribe

### Requirement: Fair use shown only when close
The iPhone app SHALL mention fair use only when an allowance is at least 80% used, with "You've used 82 of 100 hours this month. Resets Dec 1." in Settings and on the notes list. Otherwise fair use appears only in the Terms of Use, the App Store description and the unlock sheet note.

#### Scenario: Normal use
- GIVEN 20 hours used this month
- WHEN the person opens Settings
- THEN no fair-use figure appears

## Earlier buyers

### Requirement: $4.99 buyers are unlocked
A person who bought Ramble when it cost $4.99 SHALL be treated as unlocked, detected from Apple's signed record of the version they first downloaded. The app SHALL send that record automatically on first launch of the new version, and on "Restore Purchases". The same 5-inbox limit and fair use apply.

#### Scenario: Paid buyer updates
- GIVEN a person who bought Ramble for $4.99
- WHEN they open the updated app for the first time
- THEN the inbox is unlocked with no purchase
- AND the app shows once: "You're all set. You bought Ramble early, so every note transcribes. No unlock needed."

#### Scenario: Free download
- GIVEN a person whose first download was the free version
- WHEN the app checks their record
- THEN they get the 25 free notes like everyone else

### Requirement: Old subscribers are unlocked and told how to stop billing
A person with any verified purchase of the old monthly cloud subscription, active or lapsed, SHALL be treated as unlocked. Apple keeps billing an active subscription until the person cancels it, so while it is still set to renew, the app SHALL tell them once with a full-screen notice, and keep a row in Settings, until it no longer renews.

#### Scenario: Active subscriber updates
- GIVEN a person whose old subscription is still set to renew
- WHEN they open the updated app
- THEN the inbox is unlocked
- AND they see: "Cloud transcription is now included for everyone. You don't need your subscription anymore. Apple keeps billing it until you cancel." with "Manage subscription" and "Not now"
- AND "Manage subscription" opens Apple's subscription settings

#### Scenario: Reminder in Settings
- GIVEN that person tapped "Not now"
- WHEN they open Settings
- THEN a row reads "Your old subscription is still active" and opens Apple's subscription settings

#### Scenario: After cancelling
- GIVEN the subscription no longer renews
- WHEN the person opens Settings
- THEN the row is gone and Settings shows "Unlocked"

## What Ramble says about price

### Requirement: One price story everywhere
The app, website, Terms of Use, Privacy Policy and App Store listing SHALL describe pricing as "Free to download. 25 notes free, then $14.99 once." (the app uses the store's local price). Fair use SHALL be stated in the Terms of Use and the App Store description. No copy SHALL mention a monthly price, cloud upgrade, or on-device transcription.

#### Scenario: Terms page
- WHEN someone reads the Terms of Use
- THEN it states the free notes, the one-time unlock, fair use with its hours, and that refunds are handled by Apple
- AND it says nothing about auto-renewal

### Requirement: Words to avoid
Copy SHALL NOT call the free notes a "trial", and SHALL NOT say "unlimited" (fair use applies), "premium", "Subscribe", or "per month". "Subscription" SHALL appear only in "No subscription." and in messages to people who had the old one.

#### Scenario: Out of free notes
- GIVEN a person with 0 free notes left
- WHEN they read any screen about it
- THEN it says "Unlock to transcribe", never "your trial has ended"
