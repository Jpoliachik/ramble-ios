# Free notes and unlock

## Purpose
How Ramble is paid for: 25 free notes, then a one-time $14.99 unlock with no subscription. Covers counting free notes, notes held when free notes run out, buying and restoring the unlock, how every device learns about it, fair use (heavy-use monitoring and suspending a user by hand), early buyers (paid download or cloud subscription), and what Ramble says about price. The wire contract (status codes, reasons, purchase endpoint) is in relay-api.md; where held notes appear on screen is in watch.md and phone.md.

## Free notes

### Requirement: 25 free notes per inbox
Ramble SHALL transcribe the first 25 notes from an inbox for free, counted on the server by distinct note, at the moment an upload is accepted. Repeats of the same upload never count again, and neither does a hand retry. Notes from the person's watch and iPhone share one count.

#### Scenario: A retried upload never counts twice
- GIVEN a note that was accepted, but the device never saw the reply
- WHEN the device uploads the same note again
- THEN the server treats it as the same note and the free count does not change

### Requirement: Free note refunded only on permanent failure
The server SHALL give back a free note when that note's transcription permanently fails ("Couldn't transcribe", transcription.md). A note that transcribes as "No speech detected" SHALL use a free note like any other. A hand retry of a failed note (transcription.md) SHALL use no free note and SHALL never be held for unlock, whether it succeeds or fails.

#### Scenario: Retry with no free notes left
- GIVEN a locked inbox with 0 free notes left and a note that couldn't transcribe
- WHEN the person taps "Retry"
- THEN the note transcribes, and the inbox still has 0 free notes left

#### Scenario: Every provider fails for good
- GIVEN an inbox with 10 free notes left
- WHEN a note is accepted (9 left) and its transcription permanently fails
- THEN the inbox has 10 free notes left again

#### Scenario: A silent note counts
- GIVEN an inbox with 10 free notes left
- WHEN a note is accepted and its result is "No speech detected"
- THEN the inbox has 9 free notes left

### Requirement: Remaining count is shown on the iPhone
Before unlock, the iPhone app SHALL show the count the server last reported: in Settings as "N of 25 free notes left" with an "Unlock" button, and on Home as "N free notes left" with "Unlock" once 5 or fewer remain (placement in phone.md). Wherever the iPhone shows the count, it SHALL show "Unlock" beside it. The watch SHALL NOT show the count.

#### Scenario: Count in Settings
- GIVEN an inbox with 18 free notes left
- WHEN the person opens Settings
- THEN they see "18 of 25 free notes left" and an "Unlock" button

#### Scenario: Running low
- GIVEN an inbox with 3 free notes left
- WHEN the person opens Home
- THEN they see "3 free notes left" with "Unlock", and tapping it opens the unlock sheet

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
When an inbox with no free notes left and no unlock uploads a note, the server SHALL refuse it with payment required and reason "free_notes_used", keeping and counting nothing. The recording device SHALL keep the audio and show the note as "Unlock to send". A note SHALL NEVER be accepted and then dropped for payment reasons.

#### Scenario: 26th note on the watch
- GIVEN an inbox with 0 free notes left and no unlock
- WHEN the watch uploads a note
- THEN the server refuses it with reason "free_notes_used"
- AND the watch keeps the audio, shows its Unlock alert (watch.md), and tells the iPhone the note is held
- AND the iPhone counts it in its "notes to unlock" pill (phone.md)

#### Scenario: 26th note on the iPhone
- GIVEN an inbox with 0 free notes left and no unlock
- WHEN the iPhone uploads a note
- THEN the note shows "Unlock to send"
- AND the note screen's "Unlock" button opens the unlock sheet

### Requirement: Held notes wait quietly
A note held for unlock SHALL NOT be retried on a timer and SHALL be kept on the recording device until it uploads.

#### Scenario: No alert after days
- GIVEN a note held as "Unlock to send" for 3 days
- WHEN the device's stuck-note checks run
- THEN no alert is shown for that note

### Requirement: Held notes upload after unlock
When an inbox becomes unlocked, every device SHALL upload its held notes with no action from the person. The iPhone SHALL tell the watch about the unlock; how and when the watch retries is in watch.md.

#### Scenario: Unlock on the iPhone releases watch notes
- GIVEN the watch holds 4 notes as "Unlock to send"
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
- GIVEN a note marked "Unlock to send"
- WHEN the person opens it and taps "Unlock"
- THEN the unlock sheet opens

### Requirement: Unlock sheet
The unlock sheet SHALL show what the unlock buys ("Unlimited notes from your watch and iPhone." and "Pay once, keep it forever."), a short note signed by the developer (a thank-you note once unlocked), the price exactly as the App Store reports it for the person's storefront, the words "One-time purchase. No subscription.", "Restore Purchases", and links to the Terms of Use and Privacy Policy. It SHALL NOT show a built-in price.

#### Scenario: Price from the store
- GIVEN a storefront where the unlock costs €14,99
- WHEN the person opens the unlock sheet
- THEN the button reads "Unlock for €14,99"

#### Scenario: Store unreachable
- GIVEN the App Store price cannot be loaded
- WHEN the person opens the unlock sheet
- THEN the button reads "Unlock", disabled, above "Can't reach the App Store. Try again in a moment." with "Try again", which reloads the price

### Requirement: Results show beside their control
A purchase result SHALL show under the unlock button and a Restore result under "Restore Purchases". While a purchase is pending or finishing, its message SHALL replace the unlock button.

#### Scenario: Restore finds nothing
- GIVEN a person on the unlock sheet with nothing to restore
- WHEN they tap "Restore Purchases"
- THEN "No purchase found for this Apple ID." shows under "Restore Purchases"

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
- THEN the sheet shows "Waiting for approval. Your notes are kept and will send once it's approved."

#### Scenario: Approval arrives later
- GIVEN a pending purchase was approved while Ramble was closed
- WHEN the app next runs
- THEN it confirms the purchase with the server and held notes upload

#### Scenario: Paid, but the server can't be reached
- GIVEN the App Store purchase succeeded
- WHEN the app cannot confirm it with the server
- THEN the sheet shows "Purchase complete. Finishing setup. Your notes will send shortly."
- AND the app retries confirming each time it launches or returns to the foreground, and when Apple redelivers the purchase, until the server confirms; it runs no retry timer of its own

### Requirement: Restore Purchases
"Restore Purchases" SHALL be in Settings and on the unlock sheet, and SHALL confirm the Apple ID's unlock (or early-buyer proof) with the server for the current inbox. Once each new inbox exists, the app SHALL do the same on its own when the Apple ID already holds a purchase. Every inbox SHALL start free; a purchase reaches it only this way.

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

### Requirement: Purchase bound to inboxes, at most 10
A purchase MAY be sent from any inbox, including a fresh inbox after a reinstall; each inbox it unlocks is bound to it for good. One purchase SHALL unlock at most 10 inboxes ever, keyed on the purchase's original transaction (or the app purchase record for early buyers). Time SHALL free no spot. The operator MAY raise one purchase's cap by hand with one database command.

#### Scenario: Eleventh iPhone
- GIVEN a purchase bound to 10 inboxes, however long ago
- WHEN it is restored on an eleventh inbox
- THEN the server refuses, and the app shows "This purchase is in use on 10 iPhones. Each fresh start after a reinstall counts as one. Contact support@ramble.watch to add more."

#### Scenario: Operator raises the cap
- GIVEN that refused purchase
- WHEN the operator raises its cap to 11 and the person taps "Restore Purchases" on the eleventh inbox
- THEN the inbox is unlocked

### Requirement: Refunds remove the unlock
The server SHALL refuse any purchase record Apple marks as refunded or revoked. The server does not listen for Apple's refund notifications; when the operator revokes a refunded purchase by hand (relay-api.md "Revoked purchases"), the server SHALL remove the unlock from every inbox bound to that purchase and SHALL reject that purchase record from then on. Each inbox SHALL return to the free state with its used free-note count unchanged (notes accepted while unlocked never use free notes). Notes accepted before the refund SHALL still be transcribed, and transcripts already made stay.

#### Scenario: Refunded after running out
- GIVEN an inbox that used all 25 free notes, then unlocked and sent 40 more notes
- WHEN the operator revokes the refunded purchase
- THEN the inbox has 0 free notes left, and later uploads are refused with reason "free_notes_used" and held as "Unlock to send"
- AND the next time the app reads the account, Settings shows "0 of 25 free notes left" with "Unlock"

#### Scenario: Refunded early
- GIVEN an inbox that used 3 free notes before unlocking
- WHEN the operator revokes the refunded purchase
- THEN the inbox has 22 free notes left

### Requirement: Sandbox purchases unlock like real ones
TestFlight testers and App Review buy with sandbox purchases against the production server. The server SHALL verify a sandbox unlock purchase against Apple's root CA like any other and unlock the inbox for good, with the same binding, inbox cap and heavy-use monitoring. A sandbox unlock SHALL NOT count in revenue or purchase counts. Records from Xcode testing SHALL be rejected, and the production server SHALL accept no developer bypass key. Early-buyer proof (below) SHALL count only when Apple marks the record as Production.

#### Scenario: TestFlight tester buys the unlock
- GIVEN a TestFlight build with 0 free notes left
- WHEN the tester buys the unlock (free in sandbox)
- THEN the inbox unlocks for good, and held notes upload and transcribe

#### Scenario: Sandbox reviewer is not an early buyer
- GIVEN a sandbox app purchase record (originalAppVersion is always "1.0" in sandbox)
- WHEN the app sends it as early-buyer proof
- THEN the server ignores it, and the reviewer gets the 25 free notes and the unlock sheet like a new customer

## Fair use

Ramble has no usage limit. The Terms of Use say only that Ramble may pause uploads from a setup that abuses the service. The server watches for heavy use with an internal monthly threshold (the operator's `HEAVY_USE_HOURS` setting) and alerts the operator, who can suspend one user by hand. The product has no automatic cap and no override screen, and the threshold is never shown to people.

### Requirement: Heavy use is monitored, never refused
The server SHALL keep a tally of transcribed audio per user per calendar month (UTC), where the user is the purchase an inbox is unlocked by (counted across every inbox bound to it), or the inbox when it has none. Only notes that finish with a transcript or as "No speech detected" SHALL count, by the length the server measured ([transcription.md](transcription.md)); old-build transcriptions count toward their subscription's original transaction. When a user's tally first passes the threshold in a month, the server SHALL send the operator one alert naming the user and the month, and no further heavy-use alert for that user that month. Heavy use SHALL NOT refuse, hold or slow any note, and the person SHALL see nothing about it.

#### Scenario: Passing the threshold
- GIVEN a purchase 10 minutes under the threshold in November
- WHEN a 59-minute note from one of its inboxes transcribes
- THEN the operator gets one alert naming the purchase and "2026-11"
- AND that note and every later one transcribe as usual, with no second alert in November

#### Scenario: A new month
- GIVEN a purchase that passed the threshold in November
- WHEN its first note transcribes on December 1 (UTC)
- THEN it counts toward a fresh December tally

#### Scenario: Heavy but normal use
- GIVEN a heavy November, still under the threshold
- WHEN the person opens Settings and Home
- THEN neither mentions usage or a limit

### Requirement: The operator can suspend one user
The operator SHALL be able to suspend, and later unsuspend, a single inbox or a single purchase by hand, with one database command. A suspended purchase SHALL suspend every inbox bound to it, and an old-build subscriber by its original transaction. While suspended, every new upload and hand retry from that user, from the watch or the iPhone, SHALL be refused with `403` and reason "suspended", keeping and counting nothing (relay-api.md). Notes accepted before the suspension SHALL still transcribe and be delivered, reads and acks SHALL keep working, and every other user SHALL be unaffected. The devices SHALL treat the refusal like any other refusal for good: stop retrying, keep the audio, show "Couldn't send" (watch.md, phone.md). The operator's commands:

```bash
npx wrangler d1 execute ramble-relay --remote --command "SELECT user_id, ROUND(seconds / 3600.0, 1) AS hours FROM usage WHERE month = strftime('%Y-%m', 'now') ORDER BY seconds DESC LIMIT 20"
npx wrangler d1 execute ramble-relay --remote --command "UPDATE purchases SET suspended = 1 WHERE id = '<purchase ID>'"
npx wrangler d1 execute ramble-relay --remote --command "UPDATE inboxes SET suspended = 1 WHERE id = '<inbox ID>'"
npx wrangler d1 execute ramble-relay --remote --command "UPDATE purchases SET suspended = 0 WHERE id = '<purchase ID>'"
npx wrangler d1 execute ramble-relay --remote --command "UPDATE inboxes SET suspended = 0 WHERE id = '<inbox ID>'"
```

#### Scenario: One user suspended
- GIVEN the operator suspended the purchase bound to inboxes A and B
- WHEN the watch on A and the iPhone on B each upload a note
- THEN both are refused with reason "suspended", and each note shows "Couldn't send" with no retry
- AND an upload from any other inbox transcribes as usual

#### Scenario: Unsuspended
- GIVEN a suspended inbox
- WHEN the operator unsuspends it and the person records a new note
- THEN the new note uploads and transcribes as usual

### Requirement: Support page
The website SHALL have a page at https://ramble.watch/support that shows support@ramble.watch, and it SHALL be the App Store listing's Support URL; the mailbox SHALL be receiving mail before the app is submitted.

#### Scenario: Finding support
- GIVEN the App Store listing
- WHEN someone opens its Support URL
- THEN they see support@ramble.watch

## Early buyers

The first free build is the first build that offers free notes; its build number is FIRST_FREE_BUILD, set at release. A person's "first free-notes launch" is the first time they open a build at or above it.

### Requirement: Paid-download buyers are unlocked
A person whose first download of Ramble was a build below FIRST_FREE_BUILD SHALL be treated as unlocked, proved by Apple's signed app purchase record from the Production environment. The server SHALL read its original app version as a whole number and compare it numerically with FIRST_FREE_BUILD; a value that is not a whole number SHALL NOT count. Build numbers SHALL stay one increasing whole number shared by the iPhone and watch targets, never reset. The app SHALL send it on its own at first launch and on "Restore Purchases". The inbox cap and heavy-use monitoring apply.

#### Scenario: Paid buyer's first free-notes launch
- GIVEN a person who bought Ramble for $4.99
- WHEN they reach their first free-notes launch
- THEN the inbox is unlocked with no purchase
- AND the app shows once: "You're all set. You bought Ramble early, so there's nothing to unlock."

### Requirement: Subscribers are unlocked
A person who ever subscribed to the old monthly cloud subscription SHALL be treated as unlocked permanently, whether the subscription is still active or lapsed. The server SHALL decide this from the signed subscription transaction alone: any record of that product from the Production environment that was not refunded or revoked counts. The subscription product SHALL be accepted only as this proof, and SHALL be removed from sale on release day.

#### Scenario: Lapsed subscriber
- GIVEN a person whose subscription ended months earlier
- WHEN they reach their first free-notes launch
- THEN the inbox is unlocked with no purchase

#### Scenario: Sandbox subscription
- GIVEN a subscription record from the sandbox
- WHEN the app sends it
- THEN the server rejects it with reason "invalid_transaction"

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
The app, website, Terms of Use, Privacy Policy and App Store listing SHALL describe pricing as "Free to try. 25 notes free, then $14.99 once." (the app uses the store's local price), with no monthly price. The Terms of Use and App Store description SHALL state that refunds are handled by Apple. No copy SHALL state a usage amount, hours of audio, or a monthly allowance.

#### Scenario: Terms page
- GIVEN the published Terms of Use
- WHEN someone reads the pricing section
- THEN it states the 25 free notes, the one-time unlock, and that refunds are handled by Apple
- AND it says nothing about auto-renewal or hours of audio

### Requirement: Words to avoid
Copy SHALL NOT call the free notes a "trial", and SHALL NOT say "premium", "Subscribe", or "per month" or "/month" next to a price, and SHALL NOT mention monthly hours or any usage amount. "Subscription" SHALL appear only in "No subscription." and in messages to subscribers.

#### Scenario: Out of free notes
- GIVEN a person with 0 free notes left
- WHEN they read any screen about it
- THEN it says "Unlock to send", never "your trial has ended"
