import SwiftUI
import ShowreelKit

extension BlurRegion.Style {
    var title: String {
        switch self {
        case .blur: "Blur"
        case .pixelate: "Pixelate"
        }
    }
}

/// The blur lane (S-048): a click on an empty spot adds a blur there.
struct BlurLane: View {
    let editor: EditorModel
    let scale: TimelineScale

    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture { location in
                withMotion(Motion.select) { editor.addBlur(atEditTime: scale.seconds(at: location.x)) }
            }
            .help("Click to add a blur")
        if editor.blurs.regions.isEmpty {
            Text("Click to hide part of the screen")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, Space.sm)
                .frame(maxHeight: .infinity)
                .allowsHitTesting(false)
        }
        // Blurs are kept in source time; a cut shows them in pieces.
        ForEach(editor.blurs.regions) { blur in
            let ranges = editor.edits.editRanges(fromSource: blur.start, to: blur.end)
            ForEach(Array(ranges.enumerated()), id: \.offset) { i, range in
                BlurBlock(editor: editor, blur: blur, scale: scale, edges: (start: i == 0, end: i == ranges.count - 1))
                    .frame(width: max(scale.x(at: range.upperBound - range.lowerBound), 1))
                    .offset(x: scale.x(at: range.lowerBound)) // grid: ok position from time
            }
        }
    }
}

/// One blur on the blur lane. Click selects it, so its rectangle can be
/// drawn on the canvas and its look set in the inspector; drag it to move
/// it and its edges to change its timing (S-049). A drag stops at the next blur.
struct BlurBlock: View {
    let editor: EditorModel
    let blur: BlurRegion
    let scale: TimelineScale
    let edges: (start: Bool, end: Bool)
    @State private var dragStart: BlurTrack?

    private var isSelected: Bool { editor.selectedBlur == blur.id }
    private var duration: Double { editor.sources?.duration ?? editor.edits.sourceDuration }

    var body: some View {
        Block(kind: .blur, title: blur.style.title)
            .overlay {
                if isSelected {
                    Radius.shape(Radius.xs).strokeBorder(Palette.accent, lineWidth: Layout.selectionRing)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { withMotion(Motion.select) { editor.selectBlur(blur.id) } }
            .gesture(drag(named: "Move Blur") { start, seconds in
                start.moving(blur.id, by: seconds, duration: duration)
            })
            .overlay(alignment: .leading) { if edges.start { handle(.start) } }
            .overlay(alignment: .trailing) { if edges.end { handle(.end) } }
            .contextMenu {
                Button("Edit Blur") { editor.selectBlur(blur.id) }
                Button("Delete") {
                    editor.selectBlur(blur.id)
                    editor.deleteSelectedBlur()
                }
            }
            .help("\(blur.style.title), \(ClipBlock.length(blur.length)). Click to edit, drag to move.")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Blur, \(blur.style.title), \(ClipBlock.length(blur.length))")
            .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
            .accessibilityAction { editor.selectBlur(blur.id) }
    }

    /// A drag that previews `change(start, seconds)` and is one undo step.
    private func drag(named name: String, _ change: @escaping (BlurTrack, Double) -> BlurTrack) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .global)
            .onChanged { value in
                let start = dragStart ?? editor.blurs
                if dragStart == nil {
                    dragStart = start
                    editor.selectBlur(blur.id)
                }
                editor.previewBlurs(change(start, scale.seconds(at: value.translation.width)))
            }
            .onEnded { _ in
                if let start = dragStart { editor.commitBlurs(from: start, named: name) }
                dragStart = nil
            }
    }

    private func handle(_ edge: Spans.Edge) -> some View {
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
            .gesture(drag(named: "Change Blur Timing") { start, seconds in
                start.resizing(blur.id, edge: edge, by: seconds, duration: duration)
            })
            .help(edge == .start ? "Drag to change where the blur starts" : "Drag to change where the blur ends")
    }
}
