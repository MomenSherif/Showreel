# Architecture review, 2026-11-02 (end of M9, commit c461def)

16,126 lines. The largest files are `RecordController` (463), `EditorModel` (376), `SelfTest+Editor`
(345), `Zoom` (317), `EditorTracks` (315), and `Renderer` (314); nothing is near 600. M9 added
`ShowreelKit/Blur.swift` (blur track and the shared `Spans` timing rules), `BlurBlock`,
`BlurHandle`, `InspectorBlur`, `ShowreelKit/SpeechModel.swift` (models, locator, languages),
`ShowreelEngine/WhisperTranscriber.swift` (whisper.cpp behind a plain async function), and
`Captions/` in the app (the `SpeechModels` store and its views). whisper.cpp is a vendored
binary target (`tools/fetch-whisper.sh`). One fix-log entry: a self-test that registered undo
outside a group with grouping by event off, which crashed much later in Swift's executor checks.

## One timeline selection  [Strong]  (done after this review)

Files: Editor/EditorModel.swift, EditorModel+Zoom.swift, EditorModel+Blur.swift,
EditorModel+Captions.swift, EditorTracks.swift, EditorInspector.swift.
Signal: one feature touched more than 6 files. Adding the blur lane meant adding
`selectedBlur = nil` to every other select function, the clip's tap and context menu, and the
section picker.
Problem: "one thing is selected at a time" is a rule spread over four optional properties and
the code that clears the other three. A new lane that forgets one clear leaves a zoom and a
blur selected together; the inspector then shows the first in its `if` chain and Delete acts
on another.
Proposal: one stored value; the four old names stay as computed views of it, so callers do not
change, and a select function no longer clears anything.
```swift
enum TimelineSelection: Equatable {
    case segment(EditList.Segment.ID), zoom(ZoomSegment.ID), blur(BlurRegion.ID), caption(Caption.ID)
}
var selection: TimelineSelection?
var selectedZoom: ZoomSegment.ID? {
    get { if case .zoom(let id)? = selection { id } else { nil } }
    set { if let newValue { selection = .zoom(newValue) } else if selectedZoom != nil { selection = nil } }
}
```
Benefits: locality: the next lane adds one case. Setting `selectedZoom = nil` while a blur is
selected leaves the blur alone, as before.
Proof of same behavior: the self-test's 221 checks (selection, delete, and undo for every lane),
173 unit tests, and the editor-zoom-selected, editor-blur-selected, editor-caption-selected
snapshots.
Plan: one commit.

## Shared timing for zooms and blurs  [Worth exploring]

Files: ShowreelKit/Zoom.swift, ShowreelKit/Blur.swift, Editor/EditorTracks.swift (ZoomBlock),
Editor/BlurBlock.swift.
Signal: drifted copies. `ZoomTrack.gap/moving/resizing` and `Spans` are the same rules;
`ZoomBlock` and `BlurBlock` share their drag and edge-handle code line for line.
Problem: a fix to dragging (say, snapping to the playhead) has to be made twice.
Proposal: `ZoomTrack` delegates to `Spans`; one `SpanBlock<Track>` view takes the title, the
selection, and the move and resize closures.
Why not now: zooms cover `t == end` (`segment(at:)` is inclusive) and blurs do not, so moving
zooms onto `Spans` changes which zoom a click on a shared edge selects. Needs a decision and
new zoom tests first.

## One home for app settings  [Worth exploring]  (from the M8 review)

M9 added two more keys outside `AppSettings`: `captions.model` and `captions.language` in
`SpeechModels`. The M8 card still stands; the speech choices would move with it.

## Top recommendation

One timeline selection: small, mechanical, and it removes the rule every new lane has to
remember. Done in the commit after this review.

## Considered, not recommended

- Moving `SpeechModels` into ShowreelKit: it holds URLSession tasks and observes SwiftUI
  state; the pure parts (`ModelLocator`, `CaptionLanguage`) are already in the kit and tested.
- A protocol over Apple's `Transcriber` and `WhisperTranscriber`: one call site picks between
  them in six lines; a seam with two adapters and no test double would be shallow.
- Splitting `Renderer.frame`: 314 lines with the blur step added, still one readable pipeline.
