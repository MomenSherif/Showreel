# Showreel architecture

## Targets

```text
Showreel (app: SwiftUI, AppKit panels, AVFoundation, ScreenCaptureKit) -> ShowreelKit (pure rules)
ShowreelKitTests -> ShowreelKit
```

ShowreelKit knows nothing about SwiftUI, AppKit, or AVFoundation. It holds
`ProjectFiles`, `SourceKind`, `EventLog` (events.json), `RecordingClock`
(pauses removed), `AreaRules`, `DeviceChoice`, `TimeText`, and `ProjectTitle`.
Planned before M3: a `ShowreelEngine` target for the writers, capture, and
renderer (docs/architecture-review-2026-11-01.md).

## App folders

| Folder | Holds |
| --- | --- |
| `Library/` | The Library window: grid, cards, context menu |
| `Projects/` | `ProjectStore`: project folders, thumbnails, Rename, Duplicate, Move to Trash with Undo |
| `Recording/` | Everything from the Record Panel to the saved files (below) |
| `Player/` | The project window and `BubbleCompositor` (Core Image) |
| `UI/` | Design tokens and the shared `FloatingPanel` |

## Recording

```text
RecordController (state: idle -> panel -> countdown -> recording <-> paused -> saving)
  ├─ RecordPanel / AreaSelector / Countdown / RecordingControls / CameraBubble   floating panels (FloatingPanel)
  ├─ Devices (lists, saved choice) + DeviceCapture (one AVCaptureSession per mic or camera)
  ├─ MicMeter                       15 Hz level, observed only by LevelMeter
  └─ per recording:
       Timeline (Mutex<RecordingClock>)   host clock -> recording time, shared by all tracks
       ScreenCapture (SCStream)  -> TrackWriter screen.mov, system.m4a
       DeviceCapture (mic)       -> TrackWriter mic.m4a
       DeviceCapture (camera)    -> TrackWriter camera.mov
       EventRecorder (main)      -> events.json
```

- Each `TrackWriter` owns a serial queue; capture callbacks hand it samples
  stamped in host-clock seconds. It drops samples while paused and before
  the start, and repeats the newest frame at time 0 and at the end, so a
  still screen still has a full-length video.
- Every Showreel panel sets `sharingType = .none` (snapshot mode uses
  `.readOnly`), and display filters exclude the app, so the app's own chrome
  is never recorded.
- Test, snapshot, and self-test runs (APP_STORE set) keep projects in
  /tmp/Showreel-projects and trash to /tmp/Showreel-trash.

## Seams

None with two adapters yet. The self-test drives the real capture stack
(it needs Screen Recording for the process that starts it).
