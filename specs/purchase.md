# Free notes and unlock

## Purpose
How Ramble is paid for: 25 free notes, then a one-time $14.99 unlock with no subscription. Covers counting free notes, notes held when free notes run out, buying and restoring the unlock, how every device learns about it, fair use, early buyers (paid download or cloud subscription), and what Ramble says about price. The wire contract (status codes, reasons, purchase and notification endpoints) is in relay-api.md; where held notes appear on screen is in watch.md and phone.md.

## Free notes

### Requirement: 25 free notes per inbox
Ramble SHALL transcribe the first 25 notes from an inbox for free, counted on the server by distinct note, at the moment an upload is accepted. Notes from the person's watch and iPhone share one count.

#### Scenario: A retried upload never counts twice
- GIVEN a note that was accepted, but the device never saw the reply
- WHEN the device uploads the same note again
- THEN the server treats it as the same note and the free count does not change

#### Scenario: Watch and iPhone race for the last free note
- GIVEN an inbox with 1 free note left
- WHEN the watch and the iPhone each upload a different note at the same moment
- THEN exactly one note is accepted
- AND the other is refused with nothing kept or counted on the server, and is held on its device

### Requirement: Free note refunded only on permanent failure
The server SHALL give back a free note when that note's transcription permanently fails ("Couldn't transcribe", transcription.md). A note that transcribes as "No speech detected" SHALL use a free note like any other. A hand retry of a failed note (transcription.md) SHALL count like the original note: before unlock it takes a free note when accepted, is held with "free_notes_used" when none are left, and gets it back if it fails permanently again; after unlock it counts toward fair use by measured length.

#### Scenario: Retry with no free notes left
- GIVEN a locked inbox with 0 free notes left and a note that couldn't transcribe
- WHEN the person taps "Retry"
- THEN the server refuses it with reason "free_notes_used" and the note shows "Unlock to transcribe"

#### Scenario: Every provider fails for good
- GIVEN an inbox with 10 free notes left
- WHEN a note is accepted (9 left) and its transcription permanently fails
- THEN the inbox has 10 free notes left again

#### Scenario: A silent note counts
- GIVEN an inbox with 10 free notes left
- WHEN a note is accepted and its result is "No speech detected"
- THEN the inbox has 9 free notes left

### Requirement: Remaining count is shown on the iPhone
Before unlock, the iPhone app SHALL show the count the server last reported: in Settings as "N of 25 free notes left" with an "Unlock" button, and on Home as "N free notes left" once 5 or fewer remain (placement in phone.md). The watch SHALL NOT show the count.

#### Scenario: Count in Settings
- GIVEN an inbox with 18 free notes left
- WHEN the person opens Settings
- THEN they see "18 of 25 free notes left" and an "Unlock" button

#### Scenario: Running low
- GIVEN an inbox with 3 free notes left
- WHEN the person opens Home
- THEN they see "3 free notes left", and tapping it opens the unlock sheet

### Requirement: The count belongs to the inbox
A fresh inbox SHALL start with 25 free notes. A reinstall that finds its inbox credential still on the iPhone SHALL keep the same inbox, with its free count, unlock and agents. A reinstall without it SHALL start a fresh inbox with 25 free notes; agents must be connected again (delivery.md). "Delete waiting notes" (delivery.md) SHALL NOT change the count or the unlock.

#### Scenario: Reinstall keeps the inbox
- GIVEN a person with 4 free notes left whose iPhone still holds its inbox credential
- WHEN they delete and reinstall Ramble
- THEN the inbox still has 4 free notes left and its agents stay connected

#### Scenario: Reinstall starts fresh
- GIVEN a person with 0 free notes left, no purchase, and no inbox credential left on the iPhone
- WHEN they reinstall Ramble
- THEN the fresh inbox has 25 free notes left

## Out of free notes

### Requirement: Notes over the free limit are held, never dropped
When an inbox with no free notes left and no unlock uploads a note, the server SHALL refuse it with payment required and reason "free_notes_used", keeping and counting nothing. The recording device SHALL keep the audio and show the note as "Unlock to transcribe". A note SHALL NEVER be accepted and then dropped for payment reasons.

#### Scenario: 26th note on the watch
- GIVEN an inbox with 0 free notes left and no unlock
- WHEN the watch uploads a note
- THEN the server refuses it with reason "free_notes_used"
- AND the watch keeps the audio, shows its Unlock alert (watch.md), and tells the iPhone the note is held
- AND the iPhone counts it in its "notes to unlock" pill (phone.md)

#### Scenario: 26th note on the iPhone
- GIVEN an inbox with 0 free notes left and no unlock
- WHEN the iPhone uploads a note
- THEN the note shows "Unlock to transcribe"
- AND the note screen's "Unlock" button opens the unlock sheet

### Requirement: Held notes wait quietly
A note held for unlock SHALL NOT be retried on a timer, SHALL NOT trigger stuck-note alerts on any device, and SHALL be kept on the recording device until it uploads.

#### Scenario: No alert after days
- GIVEN a note held as "Unlock to transcribe" for 3 days
- WHEN the device's stuck-note checks run
- THEN no alert is shown for that note

### Requirement: Held notes upload after unlock
When an inbox becomes unlocked, every device SHALL upload its held notes with no action from the person. The iPhone SHALL tell the watch about the unlock; how and when the watch retries is in watch.md.

#### Scenario: Unlock on the iPhone releases watch notes
- GIVEN the watch holds 4 notes as "Unlock to transcribe"
- WHEN the person buys the unlock on the iPhone and the watch hears about it
- THEN the watch uploads the 4 notes and they transcribe as usual

## The unlock purchase

### Requirement: One-time unlock, no subscription
Ramble SHALL sell one non-consumable in-app purchase, "Unlock Ramble", that transcribes every note from the inbox it is bound to permanently, with no expiry, within fair use. No subscription SHALL be for sale, and Family Sharing SHALL be off for the unlock.

#### Scenario: What the purchase buys
- GIVEN a person who bought the unlock
- WHEN they record on the watch or the iPhone a year later
- THEN the notes transcribe with no further charge, within fair use

### Requirement: Where the unlock is offered
The iPhone app SHALL open the unlock sheet from the "Unlock" button in Settings, the "Unlock" button on a held note's screen, and the "free notes left" line on Home. It SHALL NOT gate onboarding, and the watch SHALL NOT offer a purchase.

#### Scenario: From a held note
- GIVEN a note marked "Unlock to transcribe"
- WHEN the person opens it and taps "Unlock"
- THEN the unlock sheet opens

### Requirement: Unlock sheet
The unlock sheet SHALL show the price exactly as the App Store reports it for the person's storefront, the words "One-time purchase. No subscription.", a fair-use line linking to the Terms of Use, "Restore Purchases", and links to the Terms of Use and Privacy Policy. It SHALL NOT show a built-in price.

#### Scenario: Price from the store
- GIVEN a storefront where the unlock costs €14,99
- WHEN the person opens the unlock sheet
- THEN the button reads "Unlock for €14,99"

#### Scenario: Store unreachable
- GIVEN the App Store price cannot be loaded
- WHEN the person opens the unlock sheet
- THEN the button reads "Unlock", disabled, above "Can't reach the App Store. Try again in a moment."

### Requirement: Purchase outcomes
The app SHALL show the person the outcome of every purchase attempt, and no outcome SHALL lose a held note.

#### Scenario: Success
- GIVEN a person on the unlock sheet
- WHEN the purchase completes and the server confirms it
- THEN the sheet shows "Unlocked" and closes, and held notes upload

#### Scenario: Cancelled
- GIVEN a person on the unlock sheet
- WHEN they cancel the App Store sheet
- THEN the unlock sheet stays open with no error

#### Scenario: Failed
- GIVEN a person on the unlock sheet
- WHEN the App Store reports the purchase failed
- THEN the sheet shows "Purchase didn't go through. Try again." and held notes stay held

#### Scenario: Pending or Ask to Buy
- GIVEN an account whose purchase needs approval, or a pending payment
- WHEN the purchase is submitted
- THEN the sheet shows "Waiting for approval. Your notes are kept and will transcribe once it's approved."

#### Scenario: Approval arrives later
- GIVEN a pending purchase was approved while Ramble was closed
- WHEN the app next runs
- THEN it confirms the purchase with the server and held notes upload

#### Scenario: Paid, but the server can't be reached
- GIVEN the App Store purchase succeeded
- WHEN the app cannot confirm it with the server
- THEN the sheet shows "Purchase complete. Finishing setup. Your notes will transcribe shortly."
- AND the app retries confirming each time it opens or comes online until the server confirms

### Requirement: Restore Purchases
"Restore Purchases" SHALL be in Settings and on the unlock sheet, and SHALL confirm the Apple ID's unlock (or early-buyer proof) with the server for the current inbox. On first launch the app SHALL do the same on its own when the Apple ID already holds a purchase.

#### Scenario: New iPhone
- GIVEN a person who bought the unlock on another iPhone
- WHEN they install Ramble on a new iPhone and launch it
- THEN the inbox is unlocked without tapping anything, and Settings shows "Unlocked"

#### Scenario: Nothing to restore
- GIVEN an Apple ID that never bought the unlock and is not an early buyer
- WHEN the person taps "Restore Purchases"
- THEN the app shows "No purchase found for this Apple ID."

## Entitlement

### Requirement: The server decides
The unlock SHALL live on the server, attached to inboxes. The iPhone SHALL send Apple's signed purchase record once per inbox; the server SHALL accept it only when its signature chains to Apple's root certificate and it is for Ramble and the unlock product (or the early-buyer proofs below). If the server cannot verify an entitlement, it SHALL accept nothing and answer that it is unavailable (relay-api.md).

#### Scenario: Forged purchase
- GIVEN a purchase record not signed by a chain leading to Apple's root certificate
- WHEN it is sent to the server
- THEN the server rejects it and the inbox stays locked

### Requirement: Purchase bound to inboxes, at most 5
A first purchase SHALL carry the account token the server gave the inbox it was bought from. A restore MAY come from a different inbox, including a fresh inbox after a reinstall, and counts toward the cap. One purchase SHALL unlock at most 5 inboxes, counting only inboxes that uploaded a note in the last 90 days, keyed on the purchase's original transaction (or the app purchase record for early buyers).

#### Scenario: First purchase from the wrong inbox
- GIVEN a first purchase whose account token does not match the inbox sending it
- WHEN it is sent to the server
- THEN the server rejects it

#### Scenario: Sixth iPhone
- GIVEN a purchase bound to 5 inboxes that uploaded in the last 90 days
- WHEN it is restored on a sixth inbox
- THEN the server refuses, and the app shows "This purchase is in use on 5 iPhones. Each fresh start after a reinstall counts as one. A spot opens when one of them goes 90 days without sending a note."

### Requirement: Refunds remove the unlock
When Apple reports a refund or revocation through its server notifications (endpoint in relay-api.md), the server SHALL remove the unlock from every inbox bound to that purchase and SHALL reject that purchase record from then on. Each inbox SHALL return to the free state with its used free-note count unchanged (notes accepted while unlocked never use free notes). Notes accepted before the refund SHALL still be transcribed, and transcripts already made stay.

#### Scenario: Refunded after running out
- GIVEN an inbox that used all 25 free notes, then unlocked and sent 40 more notes
- WHEN Apple notifies the server of a refund
- THEN the inbox has 0 free notes left, and later uploads are refused with reason "free_notes_used" and held as "Unlock to transcribe"
- AND the next time the app reads the account, Settings shows "0 of 25 free notes left" with "Unlock"

#### Scenario: Refunded early
- GIVEN an inbox that used 3 free notes before unlocking
- WHEN Apple notifies the server of a refund
- THEN the inbox has 22 free notes left

### Requirement: Test purchases never unlock production
The production server SHALL reject purchase records and server notifications from the App Store sandbox and from Xcode testing, and SHALL accept no developer bypass key. A separate test server SHALL accept sandbox records.

#### Scenario: Sandbox record in production
- GIVEN a purchase made with a sandbox account
- WHEN it is sent to the production server
- THEN the server rejects it and the inbox stays locked

## Fair use

Fair use is an abuse guard, set far above real use. Exceptions are handled by the operator by hand; the product has no override.

### Requirement: 100 hours a month per purchase
An unlocked purchase SHALL include 100 hours of transcribed audio per calendar month (UTC), counted across every inbox bound to it and resetting on the 1st. Duration SHALL be measured by the server from the transcription result, never taken from the device. There SHALL be no separate per-device limit, and before purchase only the 25 free notes apply.

#### Scenario: The note that crosses the line
- GIVEN 99.5 hours used this month
- WHEN a 60-minute note is accepted
- THEN it transcribes in full, and only uploads after it are held

### Requirement: Over the usage limit, notes are held
When the allowance is used up, the server SHALL refuse uploads with payment required, reason "fair_use", and a retry time equal to the reset, keeping and counting nothing, and SHALL alert the operator ([transcription.md](transcription.md)). The device SHALL keep the audio, show the note as "Usage limit reached" with the detail "Ramble pauses transcription after 100 hours in a month to stop abuse. This note will transcribe on <Mon D>. If this looks wrong, contact support." (the reset date), retry at the reset time and whenever the app opens, and raise no stuck-note alert.

#### Scenario: Held until the reset
- GIVEN a purchase that has used 100 hours in November
- WHEN the iPhone uploads 3 notes on November 20
- THEN each shows "Usage limit reached" and "… This note will transcribe on Dec 1. …"
- AND the operator is alerted
- AND after December 1 (UTC) the iPhone retries, and the notes upload and transcribe

### Requirement: The limit is shown only when reached
The app SHALL NOT show usage or warn before the limit is reached. Fair use appears only in the Terms of Use, the App Store description, the unlock sheet, and on notes held by it.

#### Scenario: Heavy but normal use
- GIVEN 85 hours used in November
- WHEN the person opens Settings and Home
- THEN neither mentions usage or a limit

## Early buyers

The first free build is the first build that offers free notes; its build number is FIRST_FREE_BUILD, set at release. A person's "first free-notes launch" is the first time they open a build at or above it.

### Requirement: Paid-download buyers are unlocked
A person whose first download of Ramble was a build below FIRST_FREE_BUILD SHALL be treated as unlocked, proved by Apple's signed app purchase record. The app SHALL send it on its own at first launch and on "Restore Purchases". The 5-inbox cap and fair use apply.

#### Scenario: Paid buyer's first free-notes launch
- GIVEN a person who bought Ramble for $4.99
- WHEN they reach their first free-notes launch
- THEN the inbox is unlocked with no purchase
- AND the app shows once: "You're all set. You bought Ramble early, so every note transcribes. No unlock needed."

### Requirement: Active subscribers are unlocked
A person whose monthly cloud subscription is active or in its grace period at their first free-notes launch SHALL be treated as unlocked permanently. A lapsed subscription SHALL NOT unlock. The subscription product SHALL be accepted only as this proof.

#### Scenario: Lapsed subscriber
- GIVEN a person whose subscription ended months earlier
- WHEN they reach their first free-notes launch
- THEN they get the 25 free notes like everyone else

### Requirement: Subscribers are told how to stop billing
Apple keeps billing a subscription until the person cancels it. While an unlocked subscriber's subscription is still set to renew, the app SHALL show a one-time notice and keep a row in Settings, until it no longer renews.

#### Scenario: Active subscriber opens the app
- GIVEN a person whose subscription is still set to renew
- WHEN they reach their first free-notes launch
- THEN they see: "Cloud transcription is now included for everyone. You don't need your subscription anymore. Apple keeps billing it until you cancel." with "Manage subscription" and "Not now"
- AND "Manage subscription" opens Apple's subscription settings

#### Scenario: Reminder in Settings
- GIVEN that person tapped "Not now" and the subscription still renews
- WHEN they open Settings
- THEN a row reads "Your old subscription is still active" and opens Apple's subscription settings

## What Ramble says about price

### Requirement: One price story everywhere
The app, website, Terms of Use, Privacy Policy and App Store listing SHALL describe pricing as "Free to download. 25 notes free, then $14.99 once." (the app uses the store's local price), with no monthly price. The Terms of Use and App Store description SHALL state fair use as "100 hours of audio per calendar month" per purchase, and that refunds are handled by Apple.

#### Scenario: Terms page
- GIVEN the published Terms of Use
- WHEN someone reads the pricing section
- THEN it states the 25 free notes, the one-time unlock, fair use with its hours, and that refunds are handled by Apple
- AND it says nothing about auto-renewal

### Requirement: Words to avoid
Copy SHALL NOT call the free notes a "trial", and SHALL NOT say "unlimited" (fair use applies), "premium", "Subscribe", or "per month" or "/month" next to a price. The only monthly wording allowed is the fair-use line "100 hours of audio per calendar month" and the held-note detail. "Subscription" SHALL appear only in "No subscription." and in messages to subscribers.

#### Scenario: Out of free notes
- GIVEN a person with 0 free notes left
- WHEN they read any screen about it
- THEN it says "Unlock to transcribe", never "your trial has ended"
