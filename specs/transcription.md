# Transcription

## Purpose
What happens to a note's audio on Ramble's server from the moment an upload is accepted until a transcript exists: which provider transcribes it, the options that shape the text, how silence, long notes and failures are handled, when the audio is deleted, and how cost is kept in check and watched. The endpoint contract is in [relay-api.md](relay-api.md); who receives the transcript is in [delivery.md](delivery.md); free notes, the unlock and fair use from the money side are in [subscription.md](subscription.md).

## Requirements

## Starting transcription

### Requirement: Transcription starts when an upload is accepted
The server SHALL start transcribing a note as soon as its upload is accepted, which happens only once the note's audio is fully stored. Nothing on the iPhone or the watch transcribes; there is no on-device transcription and no choice of model.

#### Scenario: Watch note
- GIVEN the watch uploads a 2-minute note
- WHEN the server finishes storing the audio and accepts the upload
- THEN transcription of that note starts right away on the server
- AND the note's status reads as transcribing until a transcript exists

#### Scenario: Interrupted upload
- GIVEN an upload breaks off halfway through the audio
- WHEN the server sees the incomplete upload
- THEN no note exists on the server, nothing is transcribed, and no free note is used
- AND the device still has the audio and uploads it again

### Requirement: Quick transcripts come back with the upload
The server SHOULD include the transcript in the upload response when transcription finishes within 8 seconds of the upload being accepted; otherwise it SHALL answer as soon as the audio is stored and the device reads the transcript later. The response shape is in relay-api.md.

#### Scenario: Short note
- GIVEN a 30-second note
- WHEN the provider returns its transcript 3 seconds after the upload is accepted
- THEN the upload response already carries the transcript

#### Scenario: Long note
- GIVEN a 45-minute note
- WHEN transcription is still running 8 seconds after the upload is accepted
- THEN the upload response says the note is accepted and transcribing, without a transcript

### Requirement: A sweeper retries stuck notes every minute
The server SHALL check every minute for accepted notes that have no transcript and are not being worked on, and SHALL start the next attempt for each one whose retry time has come. An attempt that has not finished 3 minutes after it started SHALL be treated as lost and retried.

#### Scenario: Background work cut short
- GIVEN a note's first attempt stopped before the provider answered
- WHEN the next minute's sweep runs more than 3 minutes after that attempt started
- THEN the sweep starts a new attempt for that note

### Requirement: Each note is transcribed once
The server SHALL produce at most one transcript per note ID and SHALL run at most one attempt for a note at a time. A repeated upload of the same note SHALL NOT start another transcription, and there SHALL be no way to re-transcribe a note.

#### Scenario: Retried upload after success
- GIVEN a note already has a transcript
- WHEN the device uploads the same note ID again
- THEN the server answers with the existing note and its transcript
- AND no provider is called and nothing more is counted

## Providers and fallback

### Requirement: One primary provider for everyone
The server SHALL transcribe every note with Groq Whisper v3 Turbo first, for free and unlocked inboxes alike.

#### Scenario: Normal day
- GIVEN Groq is answering normally
- WHEN any note is transcribed
- THEN Groq Whisper v3 Turbo produces its transcript

### Requirement: Fallback only when a provider is overloaded or down
The server SHALL move to the next provider in the order Groq → Deepgram Nova-3 → OpenAI GPT-Transcribe only when the current one answers with a 5xx or 429, cannot be reached, or does not answer within 120 seconds. Any other error SHALL NOT trigger a fallback. If every allowed provider fails this way, the attempt is a retryable failure.

#### Scenario: Groq rate-limits
- GIVEN Groq answers a note with 429
- WHEN the attempt continues
- THEN the same audio is sent to Deepgram Nova-3

#### Scenario: Audio rejected
- GIVEN Groq answers 400 because it cannot decode the audio
- WHEN the attempt ends
- THEN no other provider is tried and the note fails permanently

#### Scenario: Note too long for the last fallback
- GIVEN a 40-minute note, and Groq and Deepgram are both failing with 5xx
- WHEN the attempt reaches OpenAI, which accepts at most 25 minutes of audio per request
- THEN OpenAI is skipped for this note and the attempt ends as a retryable failure

### Requirement: Spend circuit breaker on the fallbacks
The server SHALL stop using Deepgram and OpenAI for the rest of the UTC day once their combined estimated spend that day reaches $5.00. While the breaker is open, notes that Groq cannot take wait and are retried with Groq only. Groq itself is capped by its own console spend limit.

#### Scenario: Breaker opens during a Groq outage
- GIVEN fallback spend today has reached $5.00
- WHEN Groq answers a note with 503
- THEN no fallback is called, the attempt is a retryable failure, and the operator is alerted

#### Scenario: New day
- GIVEN the breaker opened yesterday
- WHEN the UTC day changes
- THEN fallbacks are allowed again

### Requirement: Only providers that don't train on the audio
The server SHALL send audio only to providers whose API terms exclude using it for training, SHALL opt out of Deepgram's model improvement program on every Deepgram request, and those providers SHALL be named in the privacy policy.

#### Scenario: Deepgram fallback
- GIVEN a note falls back to Deepgram
- WHEN the server sends the audio
- THEN the request opts out of Deepgram's model improvement program

## Options

### Requirement: Options set on the iPhone apply to every note
The person SHALL be able to set three transcription options in the iPhone app's Settings: Language (default "Auto-detect"), custom vocabulary (default empty, up to 900 characters), and "Remove filler words" (default off). The server SHALL keep the current options with the inbox and SHALL apply the options in effect when a note's transcription starts, whichever device recorded it. The settings screen itself is in phone.md.

#### Scenario: Watch note uses phone settings
- GIVEN Language is set to Spanish on the iPhone
- WHEN the watch uploads a note while the phone is out of reach
- THEN the note is transcribed with a Spanish language hint

#### Scenario: Change after upload
- GIVEN a note is waiting for a retry
- WHEN the person turns on "Remove filler words"
- THEN that note's eventual transcript has filler words removed

### Requirement: Language hint
The server SHALL pass the chosen language to the provider and SHALL let the provider detect the language when the setting is "Auto-detect". When a fallback provider does not support the chosen language, the server SHALL let it auto-detect rather than force another language.

#### Scenario: Auto-detect on Deepgram
- GIVEN Language is "Auto-detect" and a note falls back to Deepgram
- WHEN the server calls Deepgram
- THEN Deepgram is asked for multilingual detection

#### Scenario: Language Deepgram lacks
- GIVEN Language is Welsh and a note falls back to Deepgram
- WHEN the server calls Deepgram
- THEN the request carries no Welsh hint and no English hint; Deepgram detects the language

### Requirement: Vocabulary hints
The server SHALL turn the custom vocabulary into a list of hint terms split on commas and line breaks, with "<" and ">" removed, spaces collapsed, duplicates dropped regardless of case (first spelling kept), each term cut to 100 characters, and at most 100 terms. The hint text SHALL never appear in the transcript as if spoken.

#### Scenario: Messy vocabulary
- GIVEN the vocabulary is "Goodloop, <Ramble>\nramble, Cloudflare   Workers"
- WHEN a note is transcribed
- THEN the provider is hinted with "Goodloop", "Ramble" and "Cloudflare Workers"

#### Scenario: Hint echoed by Whisper
- GIVEN the vocabulary is "Goodloop, Ramble"
- WHEN Groq returns a transcript ending in "Names and terms that may come up: Goodloop, Ramble."
- THEN that trailing sentence is removed from the transcript
- AND a sentence that merely ends with the word "Ramble" is kept

### Requirement: Filler-word removal
When "Remove filler words" is on, the server SHALL remove "um", "uh", "er", "ah", "hmm", "mhm", "uhm" and "erm" (including drawn-out forms like "ummm") and the punctuation that follows them, keeping words such as "like" and "you know" and keeping paragraph breaks. When it is off, filler words SHALL be kept from every provider.

#### Scenario: On
- GIVEN "Remove filler words" is on
- WHEN the spoken text is "Um, so I think, uh, we should ship it"
- THEN the transcript is "so I think, we should ship it"

#### Scenario: Off, on Deepgram
- GIVEN "Remove filler words" is off and a note falls back to Deepgram
- WHEN the transcript is produced
- THEN "um" and "uh" stay in it, as they would from Groq

### Requirement: Paragraphs
Every transcript SHALL be broken into paragraphs, with no setting. From Groq a new paragraph starts after a pause of 2 seconds or more; from Deepgram the provider's own paragraphs are used; from OpenAI, a transcript of 500 characters or more is grouped into paragraphs of about 350 characters on sentence boundaries, with a last piece under 80 characters joined to the paragraph before it. Leading and trailing whitespace is trimmed.

#### Scenario: Short note
- GIVEN a 300-character transcript from OpenAI
- WHEN it is formatted
- THEN it stays one paragraph

#### Scenario: Pause in speech
- GIVEN the person pauses for 3 seconds mid-note on Groq
- WHEN the transcript is formatted
- THEN a blank line separates the text before and after the pause

## Silent and empty audio

### Requirement: No speech detected
The server SHALL mark a note "No speech detected" when the provider returns no text, rejects the audio as too short, or returns only one of the phrases Whisper is known to invent for silence: "Thank you.", "Thanks for watching!", "Thank you for watching.", "you", "Bye.", ignoring case and surrounding punctuation. Such a note is finished with an empty transcript: it does not use a free note, no agent copy is made, and no wake-up hook fires.

#### Scenario: Pocket recording
- GIVEN a 20-second note of fabric noise
- WHEN Groq returns "Thank you."
- THEN the note is finished as "No speech detected" with an empty transcript
- AND the person's free-note count is unchanged and their agent receives nothing

#### Scenario: Real thanks inside a longer note
- GIVEN a note whose transcript is "Thank you. Remind me to call Sam tomorrow."
- WHEN it is checked
- THEN it is a normal transcript and is delivered

## Length and size

### Requirement: 60-minute cap and maximum upload size
A note SHALL be at most 60 minutes long; the recording devices stop at 60:00 (watch.md, phone.md). The server SHALL refuse an upload larger than 20 MB without storing or counting it, and SHALL transcribe any accepted upload whole, without splitting it.

#### Scenario: Full-length note
- GIVEN a 60-minute note recorded at Ramble's pinned bitrate of 32 kbps or less (about 15 MB)
- WHEN it is uploaded
- THEN it is accepted and transcribed in one piece

#### Scenario: Oversized upload
- GIVEN an upload of 30 MB
- WHEN it reaches the server
- THEN it is refused as too large, nothing is stored, and no free note is used

### Requirement: Duration is measured on the server
The server SHALL take each note's length from the provider's response and SHALL never use a length reported by the device. When a provider reports no length, the server SHALL estimate it from the audio size at 32 kbps. The measured length is what fair use, usage numbers and spend estimates count.

#### Scenario: Device claims a short note
- GIVEN a device reports a note as 10 seconds long
- WHEN Groq reports 42 minutes of audio
- THEN 42 minutes count toward fair use

## Failures

### Requirement: Retryable failures keep retrying for 20 hours
A failed attempt SHALL be retried when every allowed provider was overloaded, down or too slow, or when a provider rejected Ramble's own credentials. Retries SHALL wait 1, 2, 5, 10 and 15 minutes, then every 30 minutes, until 20 hours after the upload was accepted; the note then fails permanently. While retrying, the person sees "Transcribing…" and the device keeps the audio.

#### Scenario: Short outage
- GIVEN all providers fail for 10 minutes
- WHEN they recover
- THEN the next retry produces the transcript with no action from the person

#### Scenario: Ramble's provider key is wrong
- GIVEN Groq answers 401
- WHEN the attempt ends
- THEN the note is retried later, not failed, and the operator is alerted

### Requirement: Permanent failures
A note SHALL fail permanently when a provider rejects the audio itself (any 4xx other than 401, 403 and 429), or when the 20-hour retry window ends. The person's devices show "Couldn't transcribe"; the audio stays on the device that recorded it; there is no retry. The free note it used SHALL be given back.

#### Scenario: Corrupt audio
- GIVEN a free note whose audio no provider can decode
- WHEN Groq answers 400
- THEN the note shows "Couldn't transcribe" and the person's free-note count goes back up by one

## Audio retention and privacy

### Requirement: Audio is deleted as soon as it is no longer needed
The server SHALL delete a note's audio as soon as the note has a transcript, is "No speech detected", or has failed permanently. Independently, storage SHALL delete any audio older than 1 day. Audio storage SHALL be private, and no endpoint SHALL return audio.

#### Scenario: Transcript ready
- GIVEN a note's transcript has just been saved
- WHEN anyone looks for the audio afterwards
- THEN the server no longer has it

#### Scenario: Delete fails
- GIVEN deleting a note's audio failed after transcription
- WHEN 1 day has passed since it was stored
- THEN the storage lifecycle deletes it

### Requirement: Logs and usage records hold no content
Server logs and usage records SHALL contain no audio and no transcript text, SHALL identify devices only by a one-way hash, and SHALL keep at most the first 200 characters of a provider's error body.

#### Scenario: Provider error logged
- GIVEN Deepgram returns a 2,000-character error body
- WHEN the server logs it
- THEN the log has the status code, a hashed device ID and at most 200 characters of the body

## Cost controls

### Requirement: Fair use limits
The server SHALL refuse new uploads, keeping nothing and counting nothing, once a purchase has 50 hours or a single device has 30 hours of measured audio in the last 30 days. Refused notes stay on the device and upload again automatically once usage falls below the limit. A note already accepted is always transcribed. What the person sees is in subscription.md; the response is in relay-api.md.

#### Scenario: Heavy month
- GIVEN a purchase has 50 hours of audio in the last 30 days
- WHEN its phone uploads another note
- THEN the upload is refused as over fair use and the note is kept on the phone

#### Scenario: Near the limit
- GIVEN a device reaches 24 hours (80%) in the last 30 days
- WHEN the next note is accepted
- THEN the response says the device is close to fair use and the operator is alerted

## Operator usage monitoring

### Requirement: Daily usage summary
Once a day, at the first cron run after 14:00 UTC, the server SHALL send the operator a summary of the previous UTC day: active devices, notes accepted, audio hours, active free and unlocked inboxes, new unlocks, notes refused for no free notes or fair use, notes per provider, fallback count, estimated spend per provider, "No speech detected" count, permanent failures, and median and 95th-percentile time from upload to transcript.

#### Scenario: Morning summary
- GIVEN yesterday 400 notes were accepted
- WHEN the first cron run after 14:00 UTC happens
- THEN the operator gets one message with yesterday's numbers and no transcript text

### Requirement: Threshold alerts with cooldown
Every cron run, the server SHALL alert the operator when any of these holds: Groq answered 429 three or more times in the last hour; any fallback was used in the last hour; the fallback breaker is open; any accepted note has waited more than 5 minutes for a transcript; estimated spend across all providers today is over $5.00; a provider rejected Ramble's credentials; a device or purchase reached 80% of fair use; or more than 3% of notes finished in the last hour (with at least 10) failed permanently. The same alert, for the same device or purchase where it applies, SHALL repeat at most once every 6 hours while it still holds.

#### Scenario: Stuck note
- GIVEN an accepted note has been transcribing for 6 minutes
- WHEN the cron runs
- THEN the operator is alerted once, and not again for 6 hours while that alert still holds

#### Scenario: Held notes don't alert
- GIVEN a note was refused because the person is out of free notes
- WHEN it waits on the device for days
- THEN no stuck-note alert fires, because the server never accepted it

### Requirement: Alerts go to one configured webhook
The server SHALL POST each summary and alert to a single alert webhook kept as a server secret, such as a phone push service or the operator's own Ramble inbox. Messages SHALL contain no transcript text and no raw device IDs. When no alert webhook is set, nothing is sent.

#### Scenario: Webhook set
- GIVEN the alert webhook is configured
- WHEN an alert fires
- THEN one POST with a short plain-text message goes to that webhook
