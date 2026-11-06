# Transcription

## Purpose
What happens to a note's audio on Ramble's server from the moment an upload is accepted until a transcript exists: which provider transcribes it, the options that shape the text, silence, length, failures, when the audio is deleted, and the cost limits and operator alerts around it. The wire contract is in [relay-api.md](relay-api.md), who receives the transcript is in [delivery.md](delivery.md), and free notes, the unlock and fair use are in [subscription.md](subscription.md).

## Starting transcription

### Requirement: Transcription starts when an upload is accepted
The server SHALL start transcribing a note as soon as its upload is accepted, which happens only once the note's audio is fully stored. All transcription happens on the server.

#### Scenario: Watch note
- GIVEN the watch uploads a 2-minute note
- WHEN the server finishes storing the audio and accepts the upload
- THEN transcription of that note starts right away
- AND the note reads as transcribing until a result exists

#### Scenario: Interrupted upload
- GIVEN an upload breaks off halfway through the audio
- WHEN the server sees the incomplete upload
- THEN no note exists on the server and nothing is transcribed or counted
- AND the device still has the audio and uploads it again

### Requirement: Quick transcripts come back with the upload
When transcription finishes within the inline wait set in relay-api.md (8 seconds), the upload response SHALL carry the transcript; otherwise the device reads it later by note ID.

#### Scenario: Short note
- GIVEN a 30-second note
- WHEN the provider returns its transcript 3 seconds after the upload is accepted
- THEN the upload response already carries the transcript

### Requirement: Stalled attempts are picked up within minutes
A note SHALL never have two attempts running at once. If an attempt produces no result within 8 minutes of starting, the server SHALL treat it as lost and start the next attempt within 1 minute. Each provider call SHALL be given up after 120 seconds.

#### Scenario: Server work cut short
- GIVEN a note's attempt stopped before the provider answered
- WHEN 8 minutes have passed since that attempt started
- THEN a new attempt for that note starts within the next minute

### Requirement: Each note is transcribed once
The server SHALL produce at most one result per note. A repeated upload of the same note SHALL NOT start another transcription, and no caller can ask for a note to be transcribed again.

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
The server SHALL move to the next provider, in the order Groq → Deepgram Nova-3 → OpenAI GPT-Transcribe, only when the current one answers 5xx or 429, rejects or lacks Ramble's key (the operator is alerted), cannot be reached, or gives no answer within 120 seconds. Any other provider error SHALL NOT trigger a fallback. Notes longer than 25 minutes SHALL skip OpenAI. No note SHALL fail permanently or be marked silent because of Ramble's own configuration.

#### Scenario: Groq rate-limits
- GIVEN Groq answers a note with 429
- WHEN the attempt continues
- THEN the same audio is sent to Deepgram Nova-3

#### Scenario: Groq key rejected
- GIVEN Groq answers 401 to Ramble's key
- WHEN the attempt continues
- THEN Deepgram is tried, the note is not failed, and the operator is alerted

#### Scenario: Audio rejected
- GIVEN Groq answers 400 because it cannot decode the audio
- WHEN the attempt ends
- THEN no other provider is tried and the note fails permanently

### Requirement: Spend circuit breaker on the fallbacks
The server SHALL stop using Deepgram and OpenAI for the rest of the UTC day once their combined estimated spend that day reaches $5.00. While the breaker is open, notes that Groq cannot take wait and are retried with Groq only.

#### Scenario: Breaker opens during a Groq outage
- GIVEN fallback spend today has reached $5.00
- WHEN Groq answers a note with 503
- THEN no fallback is called, the attempt is a retryable failure, and the operator is alerted

### Requirement: Only providers that don't train on the audio
The server SHALL send audio only to providers whose API terms exclude training on it, SHALL opt out of Deepgram's model improvement program on every Deepgram request, and the privacy policy SHALL name all three providers.

#### Scenario: Deepgram fallback
- GIVEN a note falls back to Deepgram
- WHEN the server sends the audio
- THEN the request opts out of Deepgram's model improvement program
- AND Deepgram is one of the three providers the privacy policy names

## Options

### Requirement: Options set on the iPhone apply to every note
The person SHALL be able to set three options in the iPhone app (phone.md): Language (default "Auto-detect", with every language in phone.md's Language list), Vocabulary (up to 900 characters, default empty), and "Remove filler words" (default off). They SHALL be kept with the inbox on the server. A note's options SHALL be fixed when its first attempt starts, whichever device recorded it, and every retry SHALL use those same options.

#### Scenario: Watch note uses phone settings
- GIVEN Language is set to Spanish on the iPhone
- WHEN the watch uploads a note while the phone is out of reach
- THEN the note is transcribed with a Spanish language hint

#### Scenario: Change while a note waits
- GIVEN a note's first attempt ran with "Remove filler words" off and failed
- WHEN the person turns it on before the retry
- THEN the retried note keeps its filler words, and notes whose first attempt starts afterwards lose them

### Requirement: Language hint
The server SHALL pass the chosen language to the provider, and SHALL let the provider detect the language when the setting is "Auto-detect" or when a fallback provider does not support the chosen language.

#### Scenario: Auto-detect on Deepgram
- GIVEN Language is "Auto-detect" and a note falls back to Deepgram
- WHEN Deepgram transcribes it
- THEN Deepgram detects the language, including more than one language in a note

#### Scenario: Language Deepgram lacks
- GIVEN Language is Welsh and a note falls back to Deepgram
- WHEN Deepgram transcribes it
- THEN Deepgram is given no language hint, neither Welsh nor English, and detects the language itself

### Requirement: Vocabulary hints
The server SHALL use the vocabulary as a list of terms separated by commas or line breaks, ignoring case-only duplicates and dropping "<", ">" and line breaks inside a term, up to 100 terms of up to 100 characters each. The hint SHALL never appear in the transcript unless it was spoken.

#### Scenario: Hint not echoed
- GIVEN the vocabulary is "Goodloop, Ramble"
- WHEN a note that never mentions them is transcribed
- THEN neither the terms nor a sentence listing them appear in the transcript

### Requirement: Filler-word removal
When "Remove filler words" is on, the transcript SHALL leave out "um", "uh", "er", "ah", "hmm", "mhm", "uhm" and "erm", including drawn-out forms like "ummm", and keep words such as "like" and "you know" and keep paragraph breaks. When it is off, filler words SHALL be kept whichever provider transcribed the note.

#### Scenario: On
- GIVEN "Remove filler words" is on
- WHEN the person says "Um, so I think, uh, we should ship it"
- THEN the transcript is "so I think, we should ship it"

#### Scenario: Off, on Deepgram
- GIVEN "Remove filler words" is off and a note falls back to Deepgram
- WHEN the transcript is produced
- THEN "um" and "uh" stay in it, as they would from Groq

### Requirement: Paragraphs
Every transcript SHALL be broken into paragraphs, with no setting: a new paragraph starts after a pause of 2 seconds or more. When the provider gives no timing, a transcript of 500 characters or more breaks at the first sentence end once a paragraph reaches 350 characters, and a last piece under 80 characters joins the paragraph before it. A transcript under 500 characters with no 2-second pause is one paragraph.

#### Scenario: Pause in speech
- GIVEN the person pauses for 3 seconds mid-note
- WHEN the transcript is produced
- THEN a blank line separates the text before and after the pause

## Silent notes

### Requirement: No speech detected
The server SHALL finish a note as "No speech detected", with an empty transcript and result "no_speech" (relay-api.md), when the provider returns no text, rejects the audio as too short, or returns only one of these phrases, ignoring case and surrounding punctuation: "Thank you.", "Thanks for watching!", "Thank you for watching.", "you" or "Bye.".

#### Scenario: Pocket recording
- GIVEN a 20-second note of fabric noise
- WHEN Groq returns "Thank you."
- THEN the note shows "No speech detected" with an empty transcript

#### Scenario: Real thanks inside a longer note
- GIVEN a note whose transcript is "Thank you. Remind me to call Sam tomorrow."
- WHEN its result is checked
- THEN it is a normal transcript and is delivered

### Requirement: Silent notes go nowhere
A silent note SHALL use a free note like any other (subscription.md) and SHALL get no agent copy, no wake-up hook and no webhook (delivery.md).

#### Scenario: Agent connected
- GIVEN an agent is connected
- WHEN a note finishes as "No speech detected"
- THEN the agent receives nothing and the person's free-note count goes down by one

## Length

### Requirement: 60-minute cap
A note SHALL be at most 60 minutes long. The watch and the iPhone stop recording at 60:00 (watch.md, phone.md) and record at no more than 32 kbps, so a 60-minute note fits the 20 MB upload limit. The server SHALL refuse an upload whose audio is longer than 61 minutes or larger than the size limit, without storing or counting it (relay-api.md), and SHALL transcribe any accepted note whole, in one piece.

#### Scenario: Full-length note
- GIVEN a 60-minute note from the watch
- WHEN it is uploaded
- THEN it is accepted and transcribed as one note with one transcript

#### Scenario: Over-long upload
- GIVEN an upload whose audio runs 3 hours
- WHEN it reaches the server
- THEN it is refused as too long and nothing is stored or counted

### Requirement: Length is measured on the server
The server SHALL take each note's length from the provider's response, or from the audio file when a provider reports none, and SHALL never use a length reported by a device. No note SHALL count for more than 61 minutes. This length is what fair use, usage numbers and spend estimates count.

#### Scenario: Device claims a short note
- GIVEN a device reports a note as 10 seconds long
- WHEN Groq reports 42 minutes of audio
- THEN 42 minutes count toward fair use

## Failures

### Requirement: Retryable failures keep retrying for 20 hours
When every allowed provider is overloaded, down, slow, or unavailable to Ramble, the server SHALL wait 1, 2, 5, 10, then 15 minutes between attempts, then 30 minutes between each later attempt, until 20 hours after the upload was accepted. The note then fails permanently. While it waits, the person sees "Transcribing…".

#### Scenario: Window ends
- GIVEN a note has failed every attempt for 20 hours
- WHEN the window ends
- THEN the note fails permanently, with result "retries_exhausted" (relay-api.md)

### Requirement: Permanent failures
A note SHALL fail permanently, with result "audio_rejected", when a provider rejects the audio itself (any 4xx other than 401, 403 and 429), or with result "retries_exhausted" when the retry window ends. The person's devices show "Couldn't transcribe", with no retry, and the reason "Ramble couldn't turn this audio into text." or "Ramble couldn't reach a transcription service in time." respectively. The free note it used is given back (subscription.md). The audio stays wherever each device keeps it (watch.md, phone.md).

#### Scenario: Corrupt audio
- GIVEN a free note whose audio no provider can decode
- WHEN Groq answers 400
- THEN the note shows "Couldn't transcribe" and "Ramble couldn't turn this audio into text.", with no way to retry
- AND the person's free-note count goes back up by one

## Audio retention

### Requirement: Audio is deleted as soon as it is no longer needed
The server SHALL delete a note's audio as soon as the note has a transcript, is "No speech detected", or has failed permanently. Separately, any stored audio SHALL be deleted 1 day after it was stored. Audio storage SHALL be private, and no endpoint SHALL return audio. Usage records SHALL hold lengths, providers and outcomes but no audio or transcript text; server-wide log rules are in relay-api.md.

#### Scenario: Transcript ready
- GIVEN a note's transcript has just been saved
- WHEN anyone asks the server for the audio afterwards
- THEN the server no longer has it

#### Scenario: Delete fails
- GIVEN deleting a note's audio failed after transcription
- WHEN 1 day has passed since it was stored
- THEN the audio is deleted anyway

## Cost limits

### Requirement: Fair use counts measured audio
Fair use SHALL count each note's measured length against its purchase's monthly allowance (numbers, reset and what the person sees: subscription.md). An upload over the allowance SHALL be refused and nothing kept or counted (relay-api.md). A note already accepted SHALL always be transcribed, even if it takes the purchase over the allowance.

#### Scenario: Crossing the line
- GIVEN a purchase is 10 minutes under its allowance
- WHEN a 30-minute note is accepted
- THEN it is transcribed, and the next upload is refused as over fair use

### Requirement: Free-tier audio breaker
When free inboxes together reach 200 hours of measured audio in a UTC day, the server SHALL refuse every request to create an inbox until the next UTC day (relay-api.md) and SHALL alert the operator. Notes from existing inboxes SHALL still be transcribed.

#### Scenario: Scripted signups
- GIVEN free inboxes have used 200 hours of audio today
- WHEN another iPhone tries to set up Ramble
- THEN its setup is refused for now (phone.md shows what the person sees), the operator is alerted, and existing inboxes still get transcripts

## Operator

### Requirement: Daily usage summary
Once a day, between 14:00 and 14:05 UTC, the server SHALL send the operator a summary of the previous UTC day:
- active inboxes, notes accepted and audio hours, free versus unlocked
- new unlocks, and notes refused for free notes used or fair use
- notes and estimated spend per provider, and fallback count
- "No speech detected" count and permanent failures
- median and 95th-percentile time from upload to transcript

#### Scenario: Morning summary
- GIVEN 400 notes were accepted yesterday
- WHEN 14:00 UTC passes
- THEN by 14:05 UTC the operator gets one message with yesterday's numbers and no transcript text

### Requirement: Threshold alerts
The server SHALL check every minute and alert the operator when any of these holds:
- Groq answered 429 three or more times in the last hour
- any fallback was used in the last hour, or the fallback breaker is open
- any accepted note has waited more than 5 minutes for a result
- estimated spend across all providers today is over $5.00
- a provider rejected Ramble's key, or a key is missing
- a purchase reached 80% of its fair-use allowance, or used it up (a person is being held)
- the free-tier audio breaker tripped
- more than 3% of notes finished in the last hour failed permanently, counting only hours with at least 10 finished notes

#### Scenario: Stuck note
- GIVEN an accepted note has been transcribing for 6 minutes
- WHEN the next check runs
- THEN the operator is alerted

#### Scenario: Held notes don't alert
- GIVEN a note was refused because the person is out of free notes
- WHEN it waits on the device for days
- THEN no stuck-note alert fires, because the server never accepted it

### Requirement: Alert cooldown
The same alert, for the same purchase where it applies, SHALL repeat at most once every 6 hours while it still holds.

#### Scenario: Still stuck
- GIVEN the stuck-note alert fired at 10:00 and the note is still waiting
- WHEN checks run until 15:59
- THEN no second stuck-note alert is sent before 16:00

### Requirement: Alerts go to one external webhook
The server SHALL POST every summary and alert, including alerts defined in relay-api.md, to one alert webhook outside Ramble, such as a phone push service, configured by the operator. Messages SHALL contain no transcript text and no inbox secrets. When no alert webhook is set, nothing is sent.

#### Scenario: Webhook set
- GIVEN the alert webhook is configured
- WHEN an alert fires
- THEN one POST with a short plain-text message goes to that webhook
