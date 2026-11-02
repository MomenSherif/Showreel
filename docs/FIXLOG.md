# Fix log

## 2026-11-02 Self-test failed "the Camera Bubble is Medium by default" on this Mac
Symptom: one failing check, every run, with no code change in that area.
Cause: test, snapshot, and self-test runs used `UserDefaults.standard`, the person's real
settings. Large was picked in the real app, so the run started with Large; the runs could
also change real settings (bubble size, record toggles) if a check stopped halfway.
Fix: `Store.defaults` is the one place for app settings. With APP_STORE set it is an
empty domain of its own (`com.momensherif.showreel.testrun`), cleared at each launch.
Rule: never use `UserDefaults.standard` or `@AppStorage` for app settings; use
`Store.defaults`, so test runs start from the defaults and never touch real settings.

## 2026-11-01 Self-test crashed in SwiftData's @Query after choosing a background image
Symptom: exit 139, EXC_BAD_ACCESS in an executor check inside a `@Query` update, on the
main thread's run loop, far from any code that had changed.
Cause: the test had set `groupsByEvent = false` on the window's UndoManager and then
registered undo (choosing an image) with no group open. NSUndoManager was left broken,
and the next SwiftUI update crashed.
Fix: the test opens a group for every action while grouping by event is off, and turns
grouping back on before calling code that registers undo on its own.
Rule: with `groupsByEvent = false`, every `registerUndo` must sit inside
`beginUndoGrouping`/`endUndoGrouping`; restore grouping as soon as the grouped part ends.

## 2026-11-01 Editor played nothing after the composition builder was split
Symptom: (found by the self-test, before commit) the Editor's player was ready but empty:
seeks returned at once and the item was 0 s long.
Cause: `PlayerSources` kept each `AVAssetTrack` but not its `AVURLAsset`. The asset was
freed when loading finished, and `insertTimeRange(_:of:at:)` fails quietly for a track whose
asset is gone (the call was `try?`).
Fix: `PlayerSources.Track` holds the asset together with the track and its time range.
Rule: whoever keeps an `AVAssetTrack` keeps its `AVAsset` too; never `try?` a composition
insert without a check that something was inserted.

## 2026-11-01 Self-test "about 2 seconds long" failed now and then
Symptom: the project measured 2.4 s instead of 2 s on some runs.
Cause: the check slept a fixed 3.6 s for the 3 s Countdown, so the recorded length
depended on how quickly capture started.
Fix: it waits until the state is `.recording`, then records for 2 s.
Rule: self-test checks wait for a state, never a fixed sleep that guesses how long it takes.

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

## 2026-11-02 File menu had no Duplicate, Rename, Show in Finder, or Move to Trash
Symptom: (found by the S-036 self-test) the File menu showed only New Recording, Open,
Close, and Close All; ⌘D, ⌥⌘R, and ⌘⌫ did nothing from the menu bar.
Cause: the group was `CommandGroup(after: .saveItem)`. An app with no `DocumentGroup` has
no Save group, and SwiftUI silently drops commands placed after it.
Fix: the group is `CommandGroup(after: .newItem)`, with a divider; the self-test now checks
that each File command is in the menu.
Rule: anchor command groups only to placements the app really has, and have the self-test
read the menu bar for every new command.

## 2026-11-02 Closing the window during an export did not ask first
Symptom: (found by the S-037 self-test before it shipped) closing an editor window while
exporting closed it at once; the close guard's question never came.
Cause: the guard's closure read the editor model through `@State` from an AppKit callback.
Outside `body` it got a different `EditorModel` from the window's live one, with no export.
Fix: the guard looks the running export up by project ID (`EditorModel.runningExport(of:)`)
when the window asks.
Rule: never let a closure handed to AppKit read a SwiftUI `@State` model later; pass an ID
and look the object up, or keep the object in a reference AppKit owns.

## 2026-11-02 The self-test crashed in SwiftUI after Reduce Noise
Symptom: (S-043 self-test) the app crashed with EXC_BAD_ACCESS inside
`swift_task_isMainExecutor`, on the main run loop, in a SwiftData or Canvas view update,
right after an undo check. It looked like the voice isolation unit, but moving that out of
process did not change it.
Cause: the self-test turns `groupsByEvent` off and called an undoable action outside
`beginUndoGrouping`. NSUndoManager raised an Objective-C exception; AppKit caught it in the
run loop after it had unwound through Swift async frames, which left the concurrency
runtime's state broken, so a later main-actor check crashed.
Fix: the step is wrapped in `beginUndoGrouping` / `endUndoGrouping` like the others.
Rule: with `groupsByEvent` off, wrap every undoable call in a group. A crash in
`swift_task_isCurrentExecutor` far from your code means look for an Objective-C exception
earlier in the log.

## 2026-11-02 The self-test failed whenever someone clicked during the Countdown
Symptom: `tools/selftest.sh` failed "recording starts after the Countdown" (state `panel`)
twice in a row while the Mac was in use; the run printed `INFO Countdown cancelled by click`.
Cause: the Countdown covers the screen and cancels on any click (S-007). The self-test
records the real display, so a click from the person at the Mac cancelled the test's recording.
Fix: in a self-test run, a click on the Countdown is logged (`INFO Countdown ignored a click`)
and ignored. Escape and the shortcut still cancel. The self-test never tests cancel-by-click.
Rule: a self-test that runs on the real screen must ignore input it did not send itself.

## 2026-11-02 Cancelling an export could crash the app
Symptom: the unit tests crashed now and then (signal 11, about 2 runs in 7) with EXC_BAD_ACCESS
in `-[AVAssetReaderOutput copyNextSampleBuffer]`, called from `Exporter.pump` on the writer's
queue. The same path runs when someone clicks Cancel on a running export.
Cause: the task's cancellation handler called `reader.cancelReading()` on another thread while
a pump was inside `copyNextSampleBuffer()` on the same reader. AVAssetReader is not safe for that.
Fix: Cancel only raises a `StopFlag`. Each pump checks it between samples, marks its input
finished, and leaves the group; the reader and writer are cancelled after both pumps stopped.
10 test runs in a row passed after the fix.
Rule: never cancel an AVAssetReader from another thread while something may be reading from
it; signal the readers and cancel after they stop.
