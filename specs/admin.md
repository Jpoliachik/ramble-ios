# Admin

## Purpose
The operator's private dashboard: how Ramble is used and whether it is healthy, for Justin and for an agent acting for him. It reads the relay's database and is separate from the relay API that the apps and agents use ([relay-api.md](relay-api.md)). What it reads is described in [usage.md](usage.md) and [purchase.md](purchase.md).

## Requirements

### Requirement: Only Justin and his chosen agents get in
The admin site SHALL be reachable only through Cloudflare Access, which lets in Justin's own email (with a one-time code) and service tokens he creates for agents. Every admin request SHALL also carry a valid Access token for the admin application: signed by the Access team's keys, from that team, for that application, and not expired. A request without one SHALL get 403 and no data. Until the Access settings are configured, every request SHALL get 503.

#### Scenario: Justin opens the dashboard
- GIVEN Justin is signed in through Access with his email
- WHEN he opens the admin URL
- THEN he sees the dashboard, with "Signed in as" and his email

#### Scenario: An agent fetches the numbers
- GIVEN an agent sends a valid service token's client ID and secret
- WHEN it requests `GET /api/overview`
- THEN it gets the dashboard's numbers as JSON

#### Scenario: Someone else
- GIVEN a request with no Access token, or one that is forged, expired, or for another application
- WHEN it reaches the admin site
- THEN the response is 403 with no data

### Requirement: Read-only
The admin site SHALL NOT change any data. Requests other than GET and HEAD SHALL get 405.

#### Scenario: A POST
- GIVEN a signed-in request
- WHEN it sends `POST /api/overview`
- THEN the response is 405 and nothing changes

### Requirement: Counts and labels, never content
The admin site SHALL show only counts, durations, settings flags, purchase kinds, app labels and per-user hour totals. It SHALL NOT show any note's text, agent copy, vocabulary words, credential or note ID. A purchase or inbox ID SHALL appear only as a heaviest user's key, which is what Justin needs to suspend that user ([purchase.md](purchase.md)).

#### Scenario: A note is waiting with a transcript
- GIVEN a note in the database has transcript text
- WHEN the dashboard or `/api/overview` is loaded
- THEN neither contains the text

### Requirement: What the dashboard shows
The dashboard and `GET /api/overview` SHALL show the same numbers, computed when requested (UTC days):
- Totals: installs (and new in the last 7 days), installs that recorded a note, notes and hours, unlocked installs, connected agents, installs with an agent, agents that pulled in the last 7 days
- Active users in the last 24 hours, 7 days and 30 days, where active means recorded a note
- Per day for 30 days: installs, active users, notes; per week for 12 weeks: active users and notes
- Funnel: installed, first note, 10 notes, used all free notes, unlocked
- Purchases by kind and environment (Sandbox is TestFlight), with this week's and revoked counts
- How agents get notes, by how each last checked in ([usage.md](usage.md) "How notes reach people"): MCP connector, relay API with a wake-up hook, relay API polling, not seen since this was recorded, and hasn't checked in; each with its agents, how many pulled in the last 7 days, and installs
- The iPhone webhook: installs with a destination on, off, or not reported by an older app, in total and among installs that uploaded in the last 30 days
- Watch vs phone for 30 days: notes, average length, notes over 30 minutes
- Reliability for 7 days by result: notes, first-try share, average and longest wait from upload to final
- Health: notes waiting to be transcribed and the oldest one's age, server errors in the last hour, suspended installs and purchases
- Share of the last 30 days' notes with a language set, filler-word removal, or vocabulary
- Phone and watch app labels among installs that uploaded in the last 30 days
- The ten heaviest users this UTC month by hours, flagged past the internal heavy-use line

Each bar on the charts SHALL show its day (or week) and exact value when hovered, or tapped on a touch screen.

The internal heavy-use figure SHALL appear only here, never in the apps, website or user copy.

#### Scenario: A quiet database
- GIVEN no notes have been recorded
- WHEN Justin opens the dashboard
- THEN every number is zero, tables say "Nothing yet", and the health line reads "All clear"

#### Scenario: Reading one day's value
- GIVEN 13 notes were recorded on November 18
- WHEN Justin hovers over that day's bar on "Notes per day"
- THEN it reads "Nov 18: 13 notes"

#### Scenario: Something is stuck
- GIVEN a note has been waiting to be transcribed for 45 minutes
- WHEN Justin opens the dashboard
- THEN the health line reads "Needs a look" and shows the oldest wait as 45 min
