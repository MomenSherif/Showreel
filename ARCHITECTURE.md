# Showreel architecture

## Targets

```text
Showreel (app: SwiftUI, AppKit panels) -> ShowreelEngine (AVFoundation, Core Image, ScreenCaptureKit) -> ShowreelKit (pure rules)
ShowreelKitTests -> ShowreelKit
ShowreelEngineTests -> ShowreelEngine   (golden frames in Tests/ShowreelEngineTests/Golden/)
```

ShowreelKit knows nothing about SwiftUI, AppKit, or AVFoundation. It holds
`ProjectFiles`, `SourceKind`, `EventLog` (events.json), `RecordingClock`
(pauses removed), `AreaRules`, `DeviceChoice`, `TimeText`, `ProjectTitle`,
the bubble rules, `Style`, and the zoom rules (`ZoomTrack`, `AutoZoom`).

ShowreelEngine holds the media code, with no SwiftUI or AppKit, so
`swift test` can run it:

| Type | Does |
| --- | --- |
| `Timeline` | Host clock to recording time, shared by every track (`Mutex<RecordingClock>`) |
| `TrackWriter` | One file per track (HEVC .mov or AAC .m4a) on its own serial queue; `stats` counts appended, dropped, and late samples |
| `ScreenCapture` | The SCStream: screen frames and system audio, to their writers |
| `DeviceCapture` | One AVCaptureSession per mic or camera |
| `Renderer` | `frame(screen:camera:at:scene:size:) -> CIImage`, one output frame. The preview and the export both draw with it |
| `BubbleScene` | The bubble's path, hidden ranges, size, and shape for a whole recording |
| `BubbleCompositor` | The AVVideoCompositing adapter that feeds AVPlayer frames through `Renderer` |
| `Transcriber` | The mic file to timed words with SpeechAnalyzer (`SpeechTranscriber`, `.audioTimeRange`), on this Mac; downloads the speech model when it is missing |
| `CaptionPainter` | The caption on screen at a time: Core Text at output size, in its box, the spoken word on a pill; cached per caption and word |
| `Exporter` | Reads a composition through its video composition (so `Renderer` draws every frame) and writes MP4 (H.264), MOV (HEVC), or GIF; cancelling deletes the file |

The app keeps what needs AppKit or SwiftData: `CaptureSource` (the Record
Panel's choice resolved to a filter and pixel size), `Devices` (lists and
the saved choice), and building the `BubbleScene` from a `Project`.

## App folders

| Folder | Holds |
| --- | --- |
| `Library/` | The Library window: grid, cards, context menu |
| `Projects/` | `ProjectStore`: project folders, thumbnails, Rename, Duplicate, Move to Trash with Undo |
| `Recording/` | Everything from the Record Panel to the saved files (below) |
| `Editor/` | The project window (S-015): `EditorModel` per window, canvas (AVPlayerLayer), custom timeline, inspector. `PlayerBuilder` builds the composition and `BubbleScene`. `ExportSheet` and `EditorModel+Export` (`ExportRun`) export it (S-036); `ExportProgress` is the toolbar gauge and its progress and finished popover (S-037, S-038) |
| `UI/` | Design tokens and the shared `FloatingPanel` |

## Editor

```text
EditorWindow (finds the Project) -> EditorView
  ├─ EditorModel (@Observable, one per window): player, duration, isPlaying, inspector section
  │    └─ Playhead (@Observable): the time, 30 Hz, observed only by the time label and playhead line
  ├─ EditorCanvas      AVPlayerLayer on the canvas backdrop, frames from BubbleCompositor
  ├─ EditorTimeline    transport row, ruler (TimelineScale in Kit), playhead
  │    └─ EditorTracks  one lane per TrackKind; ClipBlock trims, selects, and splits
  └─ EditorInspector   segmented section picker, one grouped Form per section
```

Menus reach the key window's Editor through `@FocusedValue(\.editor)`.

The cut is an `EditList` (ShowreelKit): kept segments in **source time**,
stored as JSON in `Project.editsData`. Edits never touch the files. Zooms,
captions, and events are kept in source time too, so a cut shifts them for
free. `PlayerSources` loads the tracks once (holding their assets) and
builds an `AVPlayerItem` for any `EditList`, one `BubbleInstruction` per
segment with its `sourceOffset`. `EditorModel.apply(_:)` is the one door for
every edit.

The look is a `Style` (ShowreelKit), stored as JSON in `Project.styleData`.
The engine draws it: `Renderer.frame(…style: RenderStyle…)`, where
`RenderStyle` is the style plus its background picture decoded once at
canvas size. A style change swaps only the item's video composition
(`PlayerSources.videoComposition(slots:style:)`), so a slider drag redraws
live. `EditorModel+Style` gives styles the same undo and save path as the
cut: `applyStyle`, or `previewStyle` while dragging and `commitStyle` at the end.

Style parts (M4): background (gradient, color, wallpaper, image + blur),
padding, rounding, shadow or glow, crop (`CropRect`), device frame
(`DeviceChrome` in the engine, drawn with Core Graphics at output size and
cached), aspect ratio (`CanvasLayout.canvasSize` sets the render size), and
camera overrides. Presets are a second model, `StylePreset`, holding
`Style.asPreset`; the default one styles new projects in `AppModel.addProject`.

Zooms (M5) are a `ZoomTrack` (ShowreelKit) in source time, stored as JSON
in `Project.zoomsData`. Nil means never made: on the first open the editor
runs `AutoZoom.segments(from: events, duration:)` over the clicks, typing
bursts, and caret in events.json, and saves the result. They travel to the
engine in `RenderStyle.zooms`, so a zoom edit only swaps the video
composition, like a style change. The camera's motion is a `ZoomPath`
(ShowreelKit): a critically damped spring on scale and spot, worked out once
at 60 Hz for the whole recording (frames are drawn in any order when
seeking), with a dead zone for Follow Cursor so hand tremor never moves the
picture. The editor caches it per zooms and `Style.zoomSpeed`. `Renderer`
asks `RenderStyle.zoomPath.view(at:crop:)` for the visible part of the
recording and draws it into the same screen rect; the frame, background,
and camera stay put.

The cursor (S-034) is never in screen.mov (`showsCursor = false`); it is
drawn. events.json logs its position, its shape (arrow, I-beam, pointer,
matched against `NSCursor` 10 times a second), and when it was outside the
recorded area. `CursorTrack` (ShowreelKit) smooths the path with the same
spring and fades it when idle or away; `CursorScene` (engine) adds the
system's cursor pictures, which the app loads at their largest size
(`CursorSprites`), and `Renderer` draws it through the crop and the zoom.

Captions (M7) are a `CaptionTrack` (ShowreelKit) in source time, stored as
JSON in `Project.captionsData`; nil means never made. Generate Captions
(`EditorModel+Captions`, a `CaptionJob` for progress, Cancel, and errors)
runs `Transcriber` over mic.m4a, groups the words into lines of up to 42
characters with `CaptionTrack.lines` (a sentence end or a 0.8 s pause also
breaks a line), and applies them as one undo step. Each line keeps its
words' times for the spoken-word highlight. Their look is `Style.captions`
(`CaptionStyle`), so presets carry it; they reach the engine in
`RenderStyle.captions`, and `Renderer` draws them last, on the canvas, so
zooms and crops leave them in place. A caption edit only swaps the video
composition, like a zoom edit.

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

- `Renderer.frame`: three callers, `BubbleCompositor` (playback and, through
  the same video composition, `Exporter`) and the golden-frame tests. The
  export only changes the render size and frame rate
  (`PlayerSources.videoComposition(…renderSize:fps:)`); `ExporterTests`
  checks an exported frame against the preview's (SSIM). Re-record the goldens with
  `SHOWREEL_RECORD_GOLDEN=1 swift test ...` only for an intended change of look,
  and look at the PNGs before committing them.

Nothing else has two adapters yet. The self-test drives the real capture stack
(it needs Screen Recording for the process that starts it).
