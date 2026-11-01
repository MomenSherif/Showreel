# Architecture review — 2026-11-01 (end of M1, commit 10ef42c)

Survey: 4,811 lines of Swift in 38 files. The largest is
`Recording/RecordController.swift` (471), and every other file is under 300.
There are no duplicated private types and no fix log yet. There are two
targets: `ShowreelKit` (pure rules, unit-tested) and the app. The media code
(writers, capture, compositor) is `nonisolated` in the app target and is
tested only by the in-app self-test.

## Mic level in its own observable  [Strong]

Files: Recording/RecordController.swift (471 lines), Recording/DeviceToggles.swift
Signal: state that changes more than 10 times a second (`micLevel`, 15 Hz) sits on
`RecordController`, the model that the Record Panel, the Recording Controls,
the menus, and the menu bar item all observe.
Problem: every meter tick redraws all of `MicToggle`, including its glass
toggle, device menu, and help text. The meter, its timer, and its silence
detection are 30 lines of `RecordController` that have nothing to do with
recording.
Proposal:
```swift
@Observable final class MicMeter {
    private(set) var level: Double = 0     // 0...1, 15 Hz
    private(set) var silent = false        // no sound for 5 s
    func start(reading: @escaping () -> Float)   // dBFS source
    func stop()
}
// RecordController: let meter = MicMeter(); LevelMeter(meter: recorder.meter)
```
Benefits: only `LevelMeter` redraws at 15 Hz, `RecordController` drops 30
lines, and M2 and M7 (audio) reuse the meter.
Proof of same behavior: the self-test's 34 checks and the `record-panel`
snapshots (light and dark) match before and after.
Plan: one commit.

## Media engine target  [Worth exploring — do before M3]

Files: Recording/TrackWriter.swift, Recording/ScreenCapture.swift, Recording/Devices.swift (DeviceCapture), Player/BubbleCompositor.swift
Signal: a dependency cannot be replaced in a test. The writers and the compositor
can only be tested by launching the app.
Problem: M3 (the editor preview) and M6 (export) will grow the compositor into
the renderer. Golden-frame tests (S-036, SSIM > 0.98) need it in a target
that `swift test` can run.
Proposal: a `ShowreelEngine` target (depends on ShowreelKit, AVFoundation,
CoreImage, and ScreenCaptureKit). It holds `Timeline`, `TrackWriter`,
`ScreenCapture`, `DeviceCapture`, and the compositor, and exposes a public
`Renderer.frame(at:project:) -> CIImage` that the preview and the export
share.
Benefits: render tests with golden PNGs, and the preview and export cannot
drift apart.
Proof: the self-test recording checks, and the player snapshot.
Plan: (1) move the files and make their APIs public, (2) add a render test
with a golden frame.

## Writers report counters  [Worth exploring — before the 10-minute 4K/60 check]

Files: Recording/TrackWriter.swift
Signal: real-time paths should count problems, not hide them.
Problem: `write` silently skips a frame when the input is not ready, so a
dropped frame is invisible. S-007's "drops no frames" check cannot be read
from anywhere.
Proposal: `struct WriterStats { appended, dropped, late }` behind a `Mutex`,
plus `snapshot()`. The self-test fails when `dropped > 0`.
Plan: one commit, together with the engine move.

## Split RecordController  [Speculative]

Panel choices (source, devices) and the recording session (writers, clock,
events, stop/save) share one type. That is fine at 471 lines. Split it into
`RecordSetup` and `RecordingSession` if it passes 600 lines in M2.

## Top recommendation

**Mic level in its own observable.** It is small, it matches a listed signal,
and the behavior stays the same. Applied in this check-in, unattended.

## Considered, not recommended

- Protocols in front of the `.shared` singletons (`Devices`, `Permissions`,
  `StatusItem`): there is no second adapter yet, and the self-test drives the
  real ones.
- Moving `ProjectStore` into Kit: it uses AppKit (Finder, Trash, thumbnails),
  and its pure part (`ProjectFiles`) is already in Kit.

---

# Check-in at the end of M2 (commit 7955260)

The code now has 5,294 lines. The largest files are `RecordController` (445,
down from 471), `SelfTest` (312), and `RecordPanel` (291). Nothing is near
600 lines. The pure rules added in M2 (`BubbleSnap`, `HiddenRanges`, and the
`EventLog` bubble helpers) went into ShowreelKit with unit tests, as planned.

- **Media engine target**: still the top recommendation, and now due. M3 starts
  the editor preview on top of `BubbleCompositor`. Rated **Worth exploring**,
  not Strong, because it touches about 8 files and makes their APIs public. So
  it waits for the user's go-ahead instead of running unattended.
- **Split SelfTest by area** [Speculative]: it grows with every story. Split it into
  `SelfTest+Library`, `+Recording`, and `+Bubble` when it passes 450 lines.
- No Strong candidate this time, so no refactor in this check-in.

---

# Applied after M2 (user approved)

- **Media engine target**: done in 5558b3f (move, behavior unchanged: 49
  self-test checks, byte-identical player snapshots) and 86c57fb (golden
  frames). `Renderer.frame` takes a `BubbleScene` built by the app, not a
  `Project`, because `Project` is a SwiftData model the engine cannot see.
- **Writers report counters**: done. `TrackWriter.stats` counts appended,
  dropped, and late samples; the self-test fails on any drop. Its new unit
  test found a clock bug (docs/FIXLOG.md), fixed in its own commit.
