import SwiftUI
import ShowreelKit

/// The selected blur's rectangle on the canvas (S-048, S-049): drag inside
/// to move it, drag a corner or an edge to resize it, drag anywhere else on
/// the screen to draw a new one. Each drag is one undo step. An unselected
/// blur shows no outline.
struct BlurHandle: View {
    let editor: EditorModel
    let playhead: Playhead
    @State private var dragStart: BlurTrack?

    var body: some View {
        GeometryReader { geo in
            if let blur = editor.selectedBlurRegion,
               let canvas = editor.canvasGeometry(in: geo.size, inset: Space.xl) {
                // In the screen's own points: a zoom can push part of the blur
                // off screen, and its outline is clipped there.
                let map = BlurMapping(screen: CGRect(origin: .zero, size: canvas.screen.size),
                                      shown: editor.shownRect(atEditTime: playhead.time))
                let frame = map.view(blur.rect)
                ZStack(alignment: .topLeading) {
                    // The screen: dragging here draws a new rectangle.
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 2, coordinateSpace: .named(Self.space))
                            .onChanged { value in
                                let rect = CropRect.spanning(map.recording(value.startLocation), map.recording(value.location),
                                                             minSide: BlurRegion.minSide)
                                change(named: "Draw Blur") { $0.rect = rect }
                            }
                            .onEnded { _ in commit() })
                        .pointerStyle(.rectSelection)
                        .help("Drag to draw where the blur goes")
                    Rectangle()
                        .strokeBorder(Palette.accent, lineWidth: Layout.selectionRing)
                        .contentShape(Rectangle())
                        .frame(width: frame.width, height: frame.height)
                        .offset(x: frame.minX, y: frame.minY) // grid: ok follows the blur
                        .gesture(drag(.move, blur: blur, map: map, named: "Move Blur"))
                        .pointerStyle(dragStart == nil ? .grabIdle : .grabActive)
                        .help("Drag to move the blur")
                    ForEach(Self.handles, id: \.self) { handle in
                        let point = Self.point(of: handle, in: frame)
                        Circle()
                            .fill(.white)
                            .stroke(Palette.accent, lineWidth: Layout.selectionRing)
                            .frame(width: Self.knob, height: Self.knob)
                            .contentShape(Rectangle().size(width: Self.grab, height: Self.grab)
                                .offset(x: (Self.knob - Self.grab) / 2, y: (Self.knob - Self.grab) / 2)) // grid: ok centers the grab area
                            .offset(x: point.x - Self.knob / 2, y: point.y - Self.knob / 2) // grid: ok follows the blur
                            .gesture(drag(handle, blur: blur, map: map, named: "Resize Blur"))
                            .pointerStyle(.frameResize(position: Self.position(of: handle))) // grid: ok a pointer, not a place
                    }
                }
                .frame(width: canvas.screen.width, height: canvas.screen.height, alignment: .topLeading)
                .clipped()
                .coordinateSpace(.named(Self.space))
                .offset(x: canvas.screen.minX, y: canvas.screen.minY) // grid: ok follows the video
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Blur area")
                .accessibilityValue("\(Int((blur.rect.width * 100).rounded()))% by \(Int((blur.rect.height * 100).rounded()))% of the screen")
            }
        }
    }

    private static let space = "blur-canvas"
    private static let knob: CGFloat = 10
    private static let grab: CGFloat = 20
    private static let handles: [CropRect.Handle] = [.topLeading, .top, .topTrailing, .leading, .trailing,
                                                     .bottomLeading, .bottom, .bottomTrailing]

    private func drag(_ handle: CropRect.Handle, blur: BlurRegion, map: BlurMapping, named name: String) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named(Self.space))
            .onChanged { value in
                let base = (dragStart ?? editor.blurs).regions.first { $0.id == blur.id }?.rect ?? blur.rect
                let d = map.recordingDelta(value.translation)
                change(named: name) { $0.rect = base.dragging(handle, dx: d.width, dy: d.height, minSide: BlurRegion.minSide) }
            }
            .onEnded { _ in commit() }
    }

    @State private var undoName = ""

    private func change(named name: String, _ edit: (inout BlurRegion) -> Void) {
        guard let id = editor.selectedBlur else { return }
        if dragStart == nil {
            dragStart = editor.blurs
            undoName = name
        }
        editor.previewBlurs(editor.blurs.changing(id, edit))
    }

    private func commit() {
        if let start = dragStart { editor.commitBlurs(from: start, named: undoName) }
        dragStart = nil
    }

    private static func point(of handle: CropRect.Handle, in r: CGRect) -> CGPoint {
        switch handle {
        case .topLeading: CGPoint(x: r.minX, y: r.minY)
        case .top: CGPoint(x: r.midX, y: r.minY)
        case .topTrailing: CGPoint(x: r.maxX, y: r.minY)
        case .leading: CGPoint(x: r.minX, y: r.midY)
        case .trailing: CGPoint(x: r.maxX, y: r.midY)
        case .bottomLeading: CGPoint(x: r.minX, y: r.maxY)
        case .bottom: CGPoint(x: r.midX, y: r.maxY)
        case .bottomTrailing, .move: CGPoint(x: r.maxX, y: r.maxY)
        }
    }

    private static func position(of handle: CropRect.Handle) -> FrameResizePosition {
        switch handle {
        case .topLeading: .topLeading
        case .top: .top
        case .topTrailing: .topTrailing
        case .leading: .leading
        case .trailing: .trailing
        case .bottomLeading: .bottomLeading
        case .bottom: .bottom
        case .bottomTrailing, .move: .bottomTrailing
        }
    }
}

/// Between the canvas view's points and the recording's normalized
/// coordinates, through the crop and the zoom on screen now.
struct BlurMapping {
    /// The recording's place in the view.
    let screen: CGRect
    /// The part of the recording shown there, normalized to the recording.
    let shown: CropRect

    func view(_ r: CropRect) -> CGRect {
        CGRect(x: screen.minX + (r.x - shown.x) / shown.width * screen.width,
               y: screen.minY + (r.y - shown.y) / shown.height * screen.height,
               width: r.width / shown.width * screen.width,
               height: r.height / shown.height * screen.height)
    }

    func recording(_ p: CGPoint) -> CGPoint {
        CGPoint(x: shown.x + (p.x - screen.minX) / max(screen.width, 1) * shown.width,
                y: shown.y + (p.y - screen.minY) / max(screen.height, 1) * shown.height)
    }

    func recordingDelta(_ d: CGSize) -> CGSize {
        CGSize(width: d.width / max(screen.width, 1) * shown.width, height: d.height / max(screen.height, 1) * shown.height)
    }
}
