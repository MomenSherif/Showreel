# Fix log

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
