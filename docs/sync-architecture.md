# Sync architecture: watch → relay, watch ↔ iPhone

The APIs Ramble uses to move a note from the watch to the relay and the
person's history, why we picked each one, and the Apple references behind the
choice. Read this before changing `WatchRelayService`, `RelayUploadSession`,
`WatchConnectivityService` (watch), `PhoneConnectivityService` (iPhone), or
the relay's `/notes` path. The behavior these serve is in `specs/watch.md`
and `specs/relay-api.md`; this doc is the how and why.

Researched Nov 6 2026 against Apple's documentation, WWDC sessions, and Apple
DTS forum replies. Claims marked **(unverified)** have no Apple source we
could find; treat them as working assumptions and confirm with device logs.

## The problem in one paragraph

Until the cloud-only redesign, the watch's only transport was
WatchConnectivity to the iPhone, which then transcribed and delivered. On Nov
5 2026 notes sat on the watch for up to 40 minutes, then all reached the relay
within ~20 seconds of the iPhone being opened: `transferFile` is system-paced
[T1], and nothing in Apple's docs says iOS launches a suspended app to hand it
a file **(unverified either way)**. The relay now transcribes on the server,
so the phone has nothing to add on the way. The watch uploads each note
itself, and the phone becomes just another reader of the result.

## Design at a glance

| Hop | API | Why |
| --- | --- | --- |
| Watch → relay (audio) | Background `URLSession` upload task from file, `PUT /notes/:id`, started at Stop while the app is frontmost | Survives suspension; the system routes through the iPhone, then known Wi-Fi, then cellular [N1][N2][K4] |
| Relay → watch (status, transcript) | Upload response (done within 8 s), then `GET /notes/:id` with a default session: every 10 s while open, on open, in refresh passes | Most notes finish in the upload answer; long ones need a read [N2] |
| Watch → relay (account) | `GET /account` on open and in passes with held notes | Learns the unlock and the fair-use reset without the phone |
| iPhone → watch (connection) | `updateApplicationContext` with `watchToken`, `relayBaseURL`, `unlocked`, `deliveryAlertsFastMode`, `sentAt` | Latest value wins, survives relaunch, delivered in the background [A1][W1] |
| iPhone → watch (unlock) | `transferUserInfo(["type": "unlocked"])` alongside the context | Wakes the watch app in the background so held notes upload without opening it [U1][W1] |
| Watch → iPhone (note details, holds) | `sendMessage`, falling back to `transferUserInfo` | `sendMessage` wakes the iOS app now [M1][V1]; user info is the queue that survives [U1] |
| Watch → iPhone (needs a connection) | Same: `sendMessage` + `transferUserInfo` fallback | The phone mints a token with `POST /watch-token` even from a background wake, but only when `replaces` is its current token, it has none, or the watch changed; otherwise it re-sends the current token (the context carries `sentAt` so it's delivered) |
| Watch → iPhone (audio for history) | `transferFile`, best effort; on open, resend anything unconfirmed; on `requestAudio`, send right away | Playback only. The transcript never depends on it [T1] |
| iPhone → watch (receipt) | `sendMessage` when reachable, else `transferUserInfo` `["type": "received"]` | Lets the watch free audio once the note is also final |
| Relay | Note UUID is the idempotency key within an inbox | Any resend from any hop is harmless |

## Watch → relay

### Background upload from file

- `URLSessionConfiguration.background(withIdentifier:)` hands the transfer to
  a system daemon, so it continues while the app is suspended or terminated;
  only uploads **from a file** are supported in a background session [N2][N7].
- Requests from a watch app go through the paired iPhone when it's in reach,
  then known Wi-Fi, then cellular [K4]. TN3135 permits URLSession HTTP/HTTPS
  for every watch app; only low-level networking is restricted [N1].
- `isDiscretionary` is forced on for transfers *started* while the app is in
  the background [N3], and the system "is free to delay background session
  transfer" [F3]. So the upload is started at Stop, from the live app, with
  `isDiscretionary = false`. Retries started from a background pass may wait.
- Low Power Mode turns off Wi-Fi and cellular away from the iPhone, so notes
  wait until the app opens or the phone is back **(unverified, per Apple
  support docs on Low Power Mode, not developer docs)**.
- The relay may hold the answer up to 8 s for a quick transcript and clients
  must allow 30 s, so `timeoutIntervalForRequest` is 120 s. The resource
  timeout is a day, after which a retry pass starts the task again.
- `taskDescription` carries `<note id>|<token ref>`, so a relaunched app maps
  results to notes and knows which token uploaded each one. On launch the
  app reconnects the session and adopts running tasks from `allTasks` rather
  than starting duplicates.
- The response body of a background upload task arrives through
  `urlSession(_:dataTask:didReceive:)`; the status in `didCompleteWithError`.
- When the app was suspended, the system relaunches it in the background for
  the session's events; SwiftUI's `.backgroundTask(.urlSession(_:))` gives us
  that time, and we wait for `urlSessionDidFinishEvents(forBackgroundURLSession:)`
  [N4][N8].

### Retries

The watch never gives up on a note and never deletes audio because uploads
fail. Network errors and 5xx: 10 s, doubling to 5 min, while the app is open;
every open; when `NWPathMonitor` reports the path is back [N9]; and when a new
token arrives. 429 waits `Retry-After`. 402 `free_notes_used` holds until the
unlock (context, user info, or `GET /account`); 402 `fair_use` holds until the
reset in `Retry-After`. 413/415/`bad_upload` are final: stop, keep the audio
until the phone has it. 401 means the token was replaced or revoked: show "Set
up", send `needsConnection` with `replaces`, keep reading notes the old token
uploaded (the relay allows that for 30 days). Exact table: `specs/relay-api.md`.

### Background refresh

- `scheduleBackgroundRefresh`: one pending request at a time, delivered at
  the system's discretion [K2]. Budget is "approximately four tasks per hour
  for each app with a complication on the active watch face" [K3]; apps with
  a complication or in the Dock get priority and time is "not guaranteed"
  [K4]. Ramble has no complication, so expect fewer.
- We ask every 15 minutes while notes are waiting, transcribing or held over
  fair use, earlier for a fair-use reset, and a few minutes before a
  scheduled stuck-note notification so an acceptance that happened in the
  meantime cancels it. A pass retries uploads, reads transcripts, and reads
  the account when notes are held.

## WatchConnectivity (what it still carries)

### Application context: the connection

- `updateApplicationContext` keeps only the latest dictionary and delivers it
  when the counterpart next runs, including in the background [A1][W1].
  `receivedApplicationContext` survives relaunch, so the watch re-reads it at
  activation. The watch token also goes into the watch Keychain
  (`kSecAttrAccessibleAfterFirstUnlock`, so background passes can read it
  [L1]); replaced tokens are kept there while notes they uploaded are unfinished.
- An empty context is ignored, so a phone that never wrote one can't clear a
  working token.

### `sendMessage` — the wake

- Calling it "from your WatchKit extension while it is active and running
  wakes up the corresponding iOS app in the background and makes it
  reachable". Calling it from iOS does **not** wake the watch. [M1][M2]
- WWDC21: "If you send a message from your Watch app to your iOS app, and your
  iOS app is not in the foreground, your iOS app will be activated in the
  background to receive the message." [V1]
- Reachability from the watch needs the iPhone in range **and** the watch app
  in the foreground or running with high priority [M3]. Note details go out
  at Stop, from the live app, so the phone lists the note within seconds.
  From a background pass `isReachable` is usually false and the watch queues
  `transferUserInfo` instead.
- After a reboot the iPhone stays unreachable until its first unlock:
  `iOSDeviceNeedsUnlockAfterRebootForReachability` [M4]. This no longer blocks
  notes, since uploads don't go through the phone app.

### `transferUserInfo` — the durable queue

- Guaranteed, ordered queue that "continues even if the app is suspended"
  [U1][S1]. Used as the fallback for every watch → phone message, for
  receipts, and for the phone's `unlocked` nudge. Arriving user info wakes the
  watch app in the background through `WKWatchConnectivityRefreshBackgroundTask`
  [W1]; we hold the task until `hasContentPending` is false [W2].
- The watch queues at most one `needsConnection` while the phone is away
  (checked against `outstandingUserInfoTransfers`).

### `transferFile` — audio for the phone's history

- System-paced: "may throttle delivery speeds to accommodate performance and
  power concerns" [T1]; background transfers "happen opportunistically" [S1];
  DTS: "there is no way for developers to change the behavior" [F1].
- That's fine now: the audio is only for playback. Metadata is
  `["recording": "{\"id\", \"recordedAt\", \"duration\"}"]`. The receiver must
  move the file synchronously in `session(_:didReceive:)` [T3][T4].
- The watch keeps a note's audio until the note is final (done, failed,
  refused, lost) **and** the phone's receipt arrived, else 30 days after the
  final state. Each open resends unconfirmed audio; `requestAudio` from the
  phone (person tapped "Audio on watch") sends one immediately while the
  watch app is open. The phone can't wake the watch app [M1].
- Not supported in the Simulator [T1].

### Session lifecycle

- Activate as early as possible, "preferably when your app finishes
  launching", so background launches can receive data [V1].
- Delegate callbacks are serial on a background queue [D1]; the watch copies
  values out and hops to the main actor.
- watchOS: hold each `WKWatchConnectivityRefreshBackgroundTask` until the
  session is activated and `hasContentPending` is false, then complete it
  [W1][W2][G1].

## Background execution on watchOS

- Background audio: once a recording starts in the foreground, the audio
  background mode keeps the app running [K1]. A recording can't be started
  from the background [F2]. `AVAudioRecorder.record(forDuration:)` enforces the
  60-minute cap even if the app's timer is held back.
- `WKExtendedRuntimeSession` is limited to self care, mindfulness, physical
  therapy and smart alarm sessions [K5]. Not for us.

## Not used

- Routing notes through the iPhone app. Replaced by the direct upload.
- `sendMessageData` for short notes (the earlier inline path). Not needed when
  the phone doesn't transcribe.
- `transferCurrentComplicationUserInfo`: iOS → watch only, 50/day, needs a
  complication [C1].
- Push: background pushes are low priority and throttled [P1]; the watch
  polls while open instead.
- App Attest on the watch [N5][N6]: the watch token is minted by the phone,
  which attests; the token can only upload and read that watch's notes.

## Troubleshooting: why a watch note isn't moving

| Symptom | Likely cause | Apple reference |
| --- | --- | --- |
| "Set up" on the watch | No token yet (phone never ran or not past "Get started"), or the relay answered 401. Watch sends `needsConnection` each open | [M1][U1] |
| Note stays "Waiting" with the app closed | The background upload was started from a pass, so it's discretionary; open the app | [N3][F3] |
| Waiting away from the iPhone in Low Power Mode | Wi-Fi and cellular are off away from the phone | (unverified) |
| "Unlock to transcribe" persists after buying | The phone's context or `unlocked` user info hasn't reached the watch; opening the watch app reads `GET /account` | [A1][U1] |
| Transcript arrives but "Audio on watch" on the phone | `transferFile` is paced; open the watch app, or tap the row while it's open | [T1][F1] |
| Watch never retries in the background | Refresh budget is small without a complication | [K3][K4] |

## References

WatchConnectivity
- [M1] https://developer.apple.com/documentation/watchconnectivity/wcsession/sendmessage(_:replyhandler:errorhandler:)
- [M2] https://developer.apple.com/documentation/watchconnectivity/wcsession/sendmessagedata(_:replyhandler:errorhandler:)
- [M3] https://developer.apple.com/documentation/watchconnectivity/wcsession/isreachable
- [M4] https://developer.apple.com/documentation/watchconnectivity/wcsession/iosdeviceneedsunlockafterrebootforreachability
- [S1] https://developer.apple.com/documentation/watchconnectivity/wcsession
- [G1] https://developer.apple.com/documentation/watchconnectivity/transferring-data-with-watch-connectivity
- [T1] https://developer.apple.com/documentation/watchconnectivity/wcsession/transferfile(_:metadata:)
- [T3] https://developer.apple.com/documentation/watchconnectivity/wcsessiondelegate/session(_:didreceive:)
- [T4] https://developer.apple.com/documentation/watchconnectivity/wcsessionfile/fileurl
- [U1] https://developer.apple.com/documentation/watchconnectivity/wcsession/transferuserinfo(_:)
- [A1] https://developer.apple.com/documentation/watchconnectivity/wcsession/updateapplicationcontext(_:)
- [C1] https://developer.apple.com/documentation/watchconnectivity/wcsession/transfercurrentcomplicationuserinfo(_:)
- [D1] https://developer.apple.com/documentation/watchconnectivity/wcsessiondelegate
- [W1] https://developer.apple.com/documentation/watchkit/wkwatchconnectivityrefreshbackgroundtask
- [W2] https://developer.apple.com/documentation/watchconnectivity/wcsession/hascontentpending

watchOS background
- [K1] https://developer.apple.com/documentation/watchkit/enabling-background-sessions
- [K2] https://developer.apple.com/documentation/watchkit/wkapplication/schedulebackgroundrefresh(withpreferreddate:userinfo:scheduledcompletion:)
- [K3] https://developer.apple.com/documentation/watchkit/wkapplicationrefreshbackgroundtask
- [K4] https://developer.apple.com/documentation/watchos-apps/keeping-your-watchos-app-s-content-up-to-date
- [K5] https://developer.apple.com/documentation/watchkit/wkextendedruntimesession
- [P1] https://developer.apple.com/documentation/usernotifications/pushing-background-updates-to-your-app

Networking and App Attest
- [N1] https://developer.apple.com/documentation/technotes/tn3135-low-level-networking-on-watchos
- [N2] https://developer.apple.com/documentation/watchos-apps/making-background-requests
- [N3] https://developer.apple.com/documentation/foundation/urlsessionconfiguration/isdiscretionary
- [N4] https://developer.apple.com/documentation/watchkit/wkurlsessionrefreshbackgroundtask
- [N5] https://developer.apple.com/documentation/devicecheck/dcappattestservice
- [N6] https://developer.apple.com/documentation/devicecheck/establishing-your-app-s-integrity
- [N7] https://developer.apple.com/documentation/foundation/downloading-files-in-the-background
- [N8] https://developer.apple.com/documentation/swiftui/backgroundtask/urlsession(_:)
- [N9] https://developer.apple.com/documentation/network/nwpathmonitor

Data protection
- [L1] https://developer.apple.com/documentation/security/ksecattraccessibleafterfirstunlock

WWDC and forums
- [V1] WWDC21 "There and back again: Data transfer on Apple Watch" — https://developer.apple.com/videos/play/wwdc2021/10003/
- [V2] WWDC19 "Creating Independent Watch Apps" — https://developer.apple.com/videos/play/wwdc2019/208/ (recommends URLSession over WatchConnectivity for server-bound data)
- [F1] https://developer.apple.com/forums/thread/758334
- [F2] https://developer.apple.com/forums/thread/750432
- [F3] https://developer.apple.com/forums/thread/819449
