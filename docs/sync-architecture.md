# Sync architecture: watch → iPhone → relay

The APIs Ramble uses to move a note from the watch to the agent, why we picked
each one, and the Apple references behind the choice. Read this before
changing anything in `WatchConnectivityService`, `PhoneConnectivityService`,
`BackgroundTaskService`, or the relay upload path.

Researched Nov 6 2026 against Apple's documentation, WWDC sessions, and Apple
DTS forum replies. Claims marked **(unverified)** have no Apple source we
could find; treat them as working assumptions and confirm with device logs.

## The problem in one paragraph

On Nov 5 2026, watch notes sat in "Waiting for iPhone" for up to 40 minutes,
then all reached the relay within ~20 seconds of the iPhone being opened. The
watch's only transport was `WCSession.transferFile`. Apple documents that
file transfers are system-paced ("may throttle delivery speeds to accommodate
performance and power concerns" [T1]), and documents a background wake for
WatchConnectivity deliveries **only on watchOS** [W1]. Nothing in Apple's
docs says iOS launches a suspended app to hand it a `transferFile` or
`transferUserInfo` **(unverified either way)**. The only documented way for
the watch to wake the iPhone app is `sendMessage` [M1].

## Design at a glance

| Hop | Primary | Durable fallback | Why |
| --- | --- | --- | --- |
| Watch → iPhone (wake) | `sendMessage` with reply, sent at Stop while the watch app is still running | none needed: the file is already queued | Only API documented to launch the iOS app in the background [M1][V1] |
| Watch → iPhone (audio) | `sendMessageData` for notes ≤ 48 KB while reachable, plus `transferFile` always | resend after receipt timeout; watch keeps audio until the phone's receipt | Survives suspension and relaunch; queue visible via `outstandingFileTransfers` [T1][T2] |
| iPhone → watch (receipt) | reply to the wake message | `transferUserInfo` "received" | Reply is instant when reachable; userInfo is a guaranteed, ordered queue [U1][V1] |
| iPhone: run time after arrival | `beginBackgroundTask` | `BGAppRefreshTask`, `BGProcessingTask` | Finite foreground-equivalent time to transcribe and POST [B1][B2] |
| iPhone → relay | default `URLSession` inside the background task | queue retry on next launch / refresh | Background sessions are discretionary; we have run time already [N2][N3] |
| Relay | `INSERT OR IGNORE` keyed by recording id | | Resends from any hop are harmless |

## WatchConnectivity

### `sendMessage(_:replyHandler:errorHandler:)` — the wake

- Calling it "from your WatchKit extension while it is active and running
  wakes up the corresponding iOS app in the background and makes it
  reachable". Calling it from iOS does **not** wake the watch. [M1][M2]
- WWDC21 "There and back again": "If you send a message from your Watch app
  to your iOS app, and your iOS app is not in the foreground, your iOS app
  will be activated in the background to receive the message." Always pass a
  reply handler to confirm receipt. [V1]
- Reachability from the watch needs the iPhone in range **and** the watch app
  in the foreground or "running with a high priority in the background (e.g.
  workout session)". [M3] Our background audio session during recording
  counts as running; right after Stop the app is usually still frontmost.
- So the wake must go out **at Stop**, from the live app. A watch app woken by
  a `WKApplicationRefreshBackgroundTask` is not foreground or high priority,
  so a wake sent from there will most likely fail with `notReachable`
  (our inference from [M3]; Apple doesn't spell it out for refresh tasks).
- After a reboot the iPhone stays unreachable until its first unlock:
  `iOSDeviceNeedsUnlockAfterRebootForReachability` [M4].
- Payload size and timeout values are not documented; the error codes
  `payloadTooLarge` and `messageReplyTimedOut` exist [M5]. Keep it small:
  type + recording ids.

### `transferFile(_:metadata:)` — the audio

- Asynchronous, background thread. "The system attempts to send files as
  quickly as possible but may throttle delivery speeds to accommodate
  performance and power concerns." [T1]
- Background transfers "happen opportunistically" and "are not delivered
  immediately" [S1]. Apple DTS: "it is up to the system to decide when the
  operation should happen… there is no way for developers to change the
  behavior." [F1]
- `outstandingFileTransfers` survives relaunch, so we re-adopt queued
  transfers instead of sending duplicates [T2]. Errors come back in
  `session(_:didFinish:error:)` and we retry with backoff [T1].
- The receiver must move the file **synchronously** inside
  `session(_:didReceive:)`; the system deletes it when the method returns
  [T3][T4]. `PhoneConnectivityService` copies it before returning.
- Not supported in the Simulator [T1]. Timing tests need real devices.
- No documented size limit **(unverified)**. Our notes are tens of KB to ~1.5 MB.

### `transferUserInfo(_:)` — receipts, phone → watch

- Guaranteed, ordered queue that "continues even if the app is suspended"
  [U1][S1]. Good for receipts that must not be lost, but it's also
  system-paced, which is why the wake reply carries receipts first.

### Not used

- `updateApplicationContext` keeps only the latest value [A1]. Fine for state,
  wrong for a queue of notes.
- `transferCurrentComplicationUserInfo` is iOS → watch only, 50/day, and needs
  a complication [C1]. Not applicable.

### Session lifecycle

- Activate as early as possible, "preferably when your app finishes
  launching", so background launches can receive data [V1]. Both apps
  activate in their service `init`.
- The iOS delegate must implement `sessionDidBecomeInactive` and
  `sessionDidDeactivate` (and reactivate) for watch switching [S1]. Done.
- Delegate callbacks are serial on a background queue [D1].
- watchOS: hold each `WKWatchConnectivityRefreshBackgroundTask` until the
  session is activated and `hasContentPending` is false, then complete it.
  Leaving it open burns budget and can crash the app [W1][W2][G1].

## Background execution

### watchOS

- Background audio: once a recording starts in the foreground, the audio
  background mode keeps the app running [K1]. A recording can't be started
  from the background [F2].
- `scheduleBackgroundRefresh`: one pending request at a time, delivered at
  the system's discretion [K2]. Budget is "approximately four tasks per hour
  for each app with a complication on the active watch face" [K3]; apps with
  a complication or in the Dock get priority and time is "not guaranteed"
  [K4]. Ramble has no complication in v1, so expect fewer.
  **Use:** re-run the queue (resend after the receipt timeout, adopt
  receipts). **Don't rely on it** to send the wake.
- `WKExtendedRuntimeSession` is limited to self care, mindfulness, physical
  therapy and smart alarm sessions [K5]. Not for us.

### iOS

- `beginBackgroundTask(withName:expirationHandler:)`: "a finite amount of
  time"; start early, always end it [B1]. Used after a wake, after a file
  arrives, and on entering background.
- `BGAppRefreshTask`: system-scheduled, up to ~30 seconds [B2]. Launching the
  app activates WatchConnectivity, which *may* let queued files land
  **(unverified)**. Its sure value is retrying transcription and relay POSTs.
- `BGProcessingTask`: deferred, system-chosen; fallback for longer work [B2].
- `BGContinuedProcessingTask` (iOS 26) must start in the foreground from a
  user action and shows UI [B3][B4]. Can't be started by a watch wake. Not used.

### Push (not used)

Background pushes are low priority, not guaranteed, and Apple says not to send
"more than two or three per hour"; the system keeps only the newest [P1]. The
relay doesn't know a note exists until the phone uploads it, so push can't
fix watch → phone. Not worth the APNs dependency.

## Locked iPhone: data protection

- Keychain items use `kSecAttrAccessibleAfterFirstUnlock`, which Apple
  recommends "for items that need to be accessed by background applications"
  [L1]. The relay secret and App Attest key id are readable while locked,
  after the first unlock since boot.
- Files default to `completeUntilFirstUserAuthentication` [L2][L3], so the
  copied audio and the JSON store are readable while locked after first
  unlock. Before first unlock, saving fails; we send no receipt, so the watch
  keeps the note and resends.
- App Attest assertions while locked: **(unverified)**; watch device logs.

## Direct watch → relay (not used yet)

- Allowed: TN3135 permits URLSession HTTP/HTTPS for every watch app; only
  low-level networking is restricted [N1]. Requests route via the iPhone,
  then known Wi-Fi, then cellular [K4].
- Background sessions "may delay or defer" transfers; smaller is better [N2];
  `isDiscretionary` is forced on for transfers started in the background
  [N3]; DTS: the system "is free to delay background session transfer" [F3].
  WWDC19 recommends URLSession over WatchConnectivity for server-bound data
  [V2].
- App Attest is available on watchOS 9+ [N5][N6].
- Why not now: the phone does transcription (Apple Speech or the proxy with
  the phone's attestation). A watch upload means raw audio to the relay and
  server-side transcription, which changes pricing and the privacy story.
  Revisit if the device logs still show long gaps after the wake, or for
  phone-left-at-home notes over watch Wi-Fi/cellular.

## Where PR #59 stands against this

PR #59 (sendMessage wake + transferFile + reply receipts + watch refresh retry
+ iPhone `BGAppRefreshTask`) matches the documented best option. Notes:

1. **Right:** wake from the live watch app at queue time and again when the
   transfer finishes [M1][V1]; receipts in the reply [V1]; `transferFile` stays
   the durable carrier; 25s background task on the phone so transcription and
   the POST finish [B1].
2. **Expect the refresh-task wake to fail.** `wakePhone` is guarded by
   `isReachable`, so it's a no-op there, which is fine. The refresh task's
   value is the resend and receipt pass, not the wake [M3][K3].
3. **The 25s hold doesn't force WC to hand over the file** [T1][F1]. It keeps
   Ramble alive if the file arrives in that window. The per-hop log in PR #59
   will show whether files land within seconds of a wake on a locked phone.
4. **iPhone `BGAppRefreshTask`** is a cheap backup for relay retries; don't
   count on it for WC delivery.

Added on top of PR #59:

1. Watch shows "Unlock" when
   `iOSDeviceNeedsUnlockAfterRebootForReachability` is true [M4].
2. Notes up to 48 KB (about 12 s) also go as `sendMessageData` while
   reachable, with `transferFile` kept as the durable copy. The phone dedupes
   by recording id and replies with a receipt; the watch then cancels the
   queued transfer. This skips WC's file pacing. The size limit is
   undocumented, so any error just leaves it to the file transfer [M2][M5].

Deferred (Justin, Nov 6): direct watch → relay upload as a fallback when the
phone is unreachable. Decide after device testing.

## Troubleshooting: why a note isn't syncing

Start with the note's activity log on the iPhone (Details). It shows each hop
with timing, how the note arrived (message or file transfer), and whether the
phone was locked.

| Symptom | Likely cause | Apple reference |
| --- | --- | --- |
| Watch says "Unlock" | iPhone restarted and hasn't been unlocked; it's unreachable until then | [M4] |
| Stuck after the phone was out of range at Stop | Watch app was suspended by the time the phone was back, so no wake went out; only the system-paced file transfer remains | [M3][T1] |
| Long note slow, short notes fast | Notes over 48 KB go by file transfer only, which the system paces | [T1][F1] |
| "Reached iPhone" but no receipt | Phone got the file but couldn't save it (before first unlock, disk full); watch resends after 5 min | [L2] |
| Phone has it, agent doesn't | Transcription or relay POST ran out of background time; retries on next refresh or open | [B1][B2] |
| Everything slow in Low Power Mode | Background work is deferred more aggressively **(unverified)** | [B2] |
| Nothing arrives after force-quitting Ramble on the iPhone | Background launches for force-quit apps **(unverified)**; open Ramble once | [M1] |
| Watch never retries in the background | Refresh budget is small without a complication | [K3][K4] |

## References

WatchConnectivity
- [M1] https://developer.apple.com/documentation/watchconnectivity/wcsession/sendmessage(_:replyhandler:errorhandler:)
- [M2] https://developer.apple.com/documentation/watchconnectivity/wcsession/sendmessagedata(_:replyhandler:errorhandler:)
- [M3] https://developer.apple.com/documentation/watchconnectivity/wcsession/isreachable
- [M4] https://developer.apple.com/documentation/watchconnectivity/wcsession/iosdeviceneedsunlockafterrebootforreachability
- [M5] https://developer.apple.com/documentation/watchconnectivity/wcerror/code
- [S1] https://developer.apple.com/documentation/watchconnectivity/wcsession
- [G1] https://developer.apple.com/documentation/watchconnectivity/transferring-data-with-watch-connectivity
- [T1] https://developer.apple.com/documentation/watchconnectivity/wcsession/transferfile(_:metadata:)
- [T2] https://developer.apple.com/documentation/watchconnectivity/wcsession/outstandingfiletransfers
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

iOS background
- [B1] https://developer.apple.com/documentation/uikit/uiapplication/beginbackgroundtask(withname:expirationhandler:)
- [B2] https://developer.apple.com/documentation/backgroundtasks/choosing-background-strategies-for-your-app
- [B3] https://developer.apple.com/documentation/backgroundtasks/bgcontinuedprocessingtask
- [B4] https://developer.apple.com/documentation/backgroundtasks/performing-long-running-tasks-on-ios-and-ipados
- [P1] https://developer.apple.com/documentation/usernotifications/pushing-background-updates-to-your-app

Networking and App Attest
- [N1] https://developer.apple.com/documentation/technotes/tn3135-low-level-networking-on-watchos
- [N2] https://developer.apple.com/documentation/watchos-apps/making-background-requests
- [N3] https://developer.apple.com/documentation/foundation/urlsessionconfiguration/isdiscretionary
- [N4] https://developer.apple.com/documentation/watchkit/wkurlsessionrefreshbackgroundtask
- [N5] https://developer.apple.com/documentation/devicecheck/dcappattestservice
- [N6] https://developer.apple.com/documentation/devicecheck/establishing-your-app-s-integrity

Data protection
- [L1] https://developer.apple.com/documentation/security/ksecattraccessibleafterfirstunlock
- [L2] https://developer.apple.com/documentation/foundation/fileprotectiontype/completeuntilfirstuserauthentication
- [L3] https://developer.apple.com/documentation/uikit/encrypting-your-app-s-files

WWDC and forums
- [V1] WWDC21 "There and back again: Data transfer on Apple Watch" — https://developer.apple.com/videos/play/wwdc2021/10003/
- [V2] WWDC19 "Creating Independent Watch Apps" — https://developer.apple.com/videos/play/wwdc2019/208/
- [V3] WWDC25 "Finish tasks in the background" — https://developer.apple.com/videos/play/wwdc2025/227/
- [F1] https://developer.apple.com/forums/thread/758334
- [F2] https://developer.apple.com/forums/thread/750432
- [F3] https://developer.apple.com/forums/thread/819449
