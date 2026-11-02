import AppKit
import SwiftUI
import ShowreelKit

/// One caption on the captions lane, its text cut to fit (S-039). Click
/// selects it and shows it in the inspector; a double-click also puts the
/// cursor in its text. Drag it to move it and its edges to change its timing
/// (S-040); a drag stops at the next caption.
struct CaptionBlock: View {
    let editor: EditorModel
    let caption: Caption
    let scale: TimelineScale
    let edges: (start: Bool, end: Bool)
    @State private var dragStart: CaptionTrack?

    private var isSelected: Bool { editor.selectedCaption == caption.id }
    private var duration: Double { editor.sources?.duration ?? editor.edits.sourceDuration }

    var body: some View {
        Block(kind: .captions, title: caption.text)
            .overlay {
                if isSelected {
                    Radius.shape(Radius.xs).strokeBorder(Palette.accent, lineWidth: Layout.selectionRing)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                // The second click of a double-click edits the text.
                let double = (NSApp.currentEvent?.clickCount ?? 1) >= 2
                withMotion(Motion.select) { editor.selectCaption(caption.id, editText: double) }
            }
            .gesture(drag(named: "Move Caption") { start, seconds in
                start.moving(caption.id, by: seconds, duration: duration)
            })
            .overlay(alignment: .leading) { if edges.start { handle(.start) } }
            .overlay(alignment: .trailing) { if edges.end { handle(.end) } }
            .contextMenu {
                Button("Edit Caption") { editor.selectCaption(caption.id, editText: true) }
                Button("Delete") {
                    editor.selectCaption(caption.id)
                    editor.deleteSelectedCaption()
                }
            }
            .help("\(caption.text). Double-click to edit, drag to move.")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Caption, \(caption.text), \(ClipBlock.length(caption.length))")
            .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
            .accessibilityAction { editor.selectCaption(caption.id) }
            .accessibilityAction(named: "Edit Caption") { editor.selectCaption(caption.id, editText: true) }
    }

    /// A drag that previews `change(start, seconds)` and is one undo step.
    /// Global coordinates, since the block moves under the pointer.
    private func drag(named name: String, _ change: @escaping (CaptionTrack, Double) -> CaptionTrack) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .global)
            .onChanged { value in
                let start = dragStart ?? editor.captions
                if dragStart == nil {
                    dragStart = start
                    editor.selectCaption(caption.id)
                }
                editor.previewCaptions(change(start, scale.seconds(at: value.translation.width)))
            }
            .onEnded { _ in
                if let start = dragStart { editor.commitCaptions(from: start, named: name) }
                dragStart = nil
            }
    }

    /// An edge to retime by: a grab area the full height, a bar when selected.
    private func handle(_ edge: CaptionTrack.Edge) -> some View {
        Rectangle()
            .fill(.clear)
            .frame(width: Space.sm)
            .overlay {
                if isSelected {
                    Capsule().fill(Media.Track.label).frame(width: Layout.playheadWidth, height: Space.md)
                }
            }
            .contentShape(Rectangle())
            .pointerStyle(.columnResize)
            .gesture(drag(named: "Change Caption Timing") { start, seconds in
                start.resizing(caption.id, edge: edge, by: seconds, duration: duration)
            })
            .help(edge == .start ? "Drag to change when the caption appears" : "Drag to change when the caption goes away")
    }
}
