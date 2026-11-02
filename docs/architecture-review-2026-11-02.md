# Architecture review, 2026-11-02 (end of M7, commit 0209e6f)

13,637 lines. Largest: `RecordController` (449), `Snapshot` (419),
`EditorModel` (365) plus seven `EditorModel+` files, `SelfTest+Editor` (343),
`Zoom` (317), `EditorTracks` (308). Nothing is near 600. Most churned in 30
days: `Snapshot.swift` (24 commits), `EditorModel.swift` (21), `SelfTest.swift`
(17). M7 kept its rules in ShowreelKit (`CaptionTrack`, `CaptionStyle`,
`AudioMix`, `Waveform`) with unit tests, and its media work in the engine
(`Transcriber`, `CaptionPainter`, `AudioLevels`, `WaveformReader`,
`NoiseReducer`) with engine tests, as planned. One fix-log entry this
milestone (an ungrouped undo in the self-test), in an area that has not
repeated.

## One edit door for captions and audio  [Strong]

Files: Editor/EditorModel+Style.swift (`commitDrawn`), Editor/EditorModel+Captions.swift
(`commitCaptions`), Editor/EditorModel+Audio.swift (`commitAudio`)
Signal: the M4 card "One edit door for every project part" said to fold in
each new copy as it appears. M7 added two: `commitCaptions` and `commitAudio`
repeat register undo, set the action name, write JSON, save, refresh, and
refresh undo, line for line, beside `commitDrawn`.
Problem: a fix to the undo path (FIXLOG has two undo rules) has to land in
three places, and the next project part (blur regions, speed changes in
Later) would add a fourth.
Proposal: `commitDrawn` becomes `commitPart`, with the refresh as a parameter
that defaults to `redraw()`:
```swift
func commitPart<Value: Equatable & Sendable>(from old: Value, to new: Value, named: String,
    current: @escaping @Sendable @MainActor (EditorModel) -> Value,
    set: @escaping @Sendable @MainActor (EditorModel, Value) -> Void,
    refresh: @escaping @Sendable @MainActor (EditorModel, _ old: Value) -> Void = { e, _ in e.redraw() })
```
Captions use it as is (they are drawn). Audio passes a refresh that swaps the
audio mix, or rebuilds the item when Reduce Noise changes the mic's file.
Benefits: one undo path for style, zooms, captions, and audio; each part is
its `set` closure. The cut keeps `apply`, since it moves the playhead.
Proof of same behavior: the self-test's caption and audio undo checks (177
checks), the unit tests (150), and the caption and audio snapshot pages.
Plan: one commit.

## Snapshot surfaces in their own file  [Strong, next]

`Snapshot.swift` is at 419 lines (the M6 note said to act at 400) and is the
most-churned file: every story adds a surface. Move `editorSurfaces` to
`Snapshot+Editor.swift`. Mechanical; proof is the same 69 pages. Do it as the
first commit of M8.

## Open-editor registry  [Worth exploring, carried over]

No fourth caller appeared in M7 (Generate Captions stayed in the editor).
Revisit when a Library command needs an editor.

## Considered, not recommended

- **AudioLevels and the caption painter behind protocols**: each has one
  adapter, and the engine tests drive them for real (the export is checked
  for silence in a muted part and for half volume).
- **A shared "job" type for CaptionJob, NoiseJob, and ExportRun**: they share
  only progress and Cancel; their states and words differ. Three small types
  read better than one generic one.
- **Moving the waveform read into PlayerSources.load**: it would delay the
  first frame; reading it after the player is ready is the right order.

## Top recommendation

One edit door for captions and audio (Strong). Done in this check-in:
`commitDrawn` is now `EditorModel.commitPart(from:to:named:current:set:refresh:)`.
Style, zooms, and captions use the default refresh (redraw); audio passes its
own (swap the audio mix, or rebuild the item when Reduce Noise changes the
mic's file). `commitCaptions` and `commitAudio` are now just their `set` closures.
Proof: the self-test passes all 177 checks and the unit tests all 150, as
before. The caption and audio snapshots match before and after, except for the
window's focus state and a video-frame timing difference in the canvas, both
known snapshot noise.
