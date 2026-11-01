# Fix log

## 2026-11-01 Samples handled after Resume got the wrong time
Symptom: (found by the new TrackWriter test) a frame captured before a pause but written
after Resume was placed earlier than it happened, even at a negative time.
Cause: `RecordingClock` kept only the total paused time, so it applied the newest pause to
every sample, including ones captured before it. Writers handle samples on their own queue,
a moment after capture.
Fix: the clock keeps every pause and subtracts only the pauses that ended before the sample.
Rule: a clock that maps past timestamps must keep its history, not a running total.

## 2026-11-01 Snapshot and self-test runs hang with no output
Symptom: `tools/snap.sh` and `tools/selftest.sh` sometimes never finished and printed
nothing; the process sat idle with `NSApp.windows` empty.
Cause: SwiftUI sometimes opens no window at launch, even for the first `Window` scene with
`.defaultLaunchBehavior(.presented)` and no saved state. The Library's startup task, which
runs the seed data, self-test, and snapshots, then never ran. A first guess (another copy
running) was wrong: it hung with nothing else running too.
Fix: the menu commands, which exist from launch, hand their `openWindow` action to
`AppServices`, the model is set in `App.init`, and the app delegate opens the Library when
no window is visible half a second after launch. The scripts also quit a running copy and
pass `-ApplePersistenceIgnoreState YES`.
Rule: never start app-wide work from a window's first appearance alone; make sure the
window opens from AppKit, and give AppKit callers a way to open windows from launch.

## 2026-11-01 Signed app killed at launch (exit 137)
Symptom: the app vanished at launch, and the self-test exited 137.
Cause: `build.sh` picked the first "Apple Development" certificate by name, and both
certificates with that name were revoked (`spctl` said CSSMERR_TP_CERT_REVOKED).
Fix: `build.sh` signs by SHA-1 hash, skips revoked certificates, and caches the working one.
Rule: sign by hash and check `spctl -a -vv -t exec` when a launch exits 137.

## 2026-11-01 Camera hidden during a pause still showed in the video
Symptom: (found in review) hiding the Camera Bubble or moving it while paused was not logged.
Cause: `EventRecorder` stamps events with recording time, which is undefined while paused,
so those events were dropped.
Fix: bubble moves and hide/show during a pause are stamped with the pause point, so they
apply from where the video resumes.
Rule: events that change state (not samples) must never be dropped while paused.
