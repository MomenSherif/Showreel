import SwiftUI
import ShowreelKit

extension ZoomSegment.Focus {
    var title: String {
        switch self {
        case .auto: "Auto"
        case .followCursor: "Follow Cursor"
        case .fixed: "Fixed Point"
        }
    }
}

/// The selected zoom in the inspector (S-031): Scale, Focus, where it
/// looks, and Delete. Done or Esc goes back to the section.
struct ZoomInspector: View {
    let editor: EditorModel
    let zoom: ZoomSegment
    @State private var dragStart: ZoomTrack?

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: Space.xs) {
                    HStack {
                        Text("Scale")
                        Spacer()
                        Text(Lane.scaleText(zoom.scale))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: scaleBinding, in: ZoomSegment.scaleRange, onEditingChanged: { editing in
                        if editing {
                            dragStart = editor.zooms
                        } else if let start = dragStart {
                            editor.commitZooms(from: start, named: "Zoom Scale")
                            dragStart = nil
                        }
                    })
                    .labelsHidden()
                    .accessibilityLabel("Scale")
                    .accessibilityValue(Lane.scaleText(zoom.scale))
                }
                Picker("Focus", selection: focusBinding) {
                    ForEach(ZoomSegment.Focus.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            }
            Section {
                FocusPreview(editor: editor, zoom: zoom)
            } header: {
                Text("Focus Point")
            } footer: {
                Text(hint).foregroundStyle(.secondary)
            }
            Section("Timing") {
                LabeledContent("Starts", value: editor.editStart(of: zoom).map(TimeText.precise) ?? "Cut")
                LabeledContent("Length", value: ClipBlock.length(zoom.length))
            }
            Section {
                Button("Delete Zoom", role: .destructive) { editor.deleteSelectedZoom() }
                    .help("Delete Zoom (⌫)")
            }
        }
        .formStyle(.grouped)
    }

    private var hint: String {
        switch zoom.focus {
        case .auto: "Looks where you clicked or typed. Drag to choose a spot."
        case .followCursor: "Follows the cursor. Drag to choose a fixed spot instead."
        case .fixed: "Drag to move the spot."
        }
    }

    private var scaleBinding: Binding<Double> {
        Binding(get: { zoom.scale }, set: { scale in
            let track = editor.zooms(changing: zoom.id) { $0.scale = (scale * 10).rounded() / 10 }
            // Arrow keys and VoiceOver change the value without a drag: each is its own step.
            if dragStart == nil {
                editor.applyZooms(track, named: "Zoom Scale")
            } else {
                editor.previewZooms(track)
            }
        })
    }

    private var focusBinding: Binding<ZoomSegment.Focus> {
        Binding(get: { zoom.focus }, set: { focus in
            editor.applyZooms(editor.zooms(changing: zoom.id) { $0.focus = focus }, named: "Zoom Focus")
        })
    }
}

/// A small picture of the recording with the part the zoom shows outlined.
/// Dragging on it moves the spot and makes the focus a fixed point.
private struct FocusPreview: View {
    let editor: EditorModel
    let zoom: ZoomSegment
    @State private var frame: CGImage?
    @State private var dragStart: ZoomTrack?

    private var aspect: CGFloat {
        guard let size = editor.sources?.naturalSize, size.height > 0 else { return Layout.thumbnailAspect }
        return size.width / size.height
    }

    /// Where the zoom looks in the middle of the segment.
    private var spot: CGPoint {
        zoom.spot(at: (zoom.start + zoom.end) / 2, cursor: editor.sources?.scene.cursor ?? CursorPath())
    }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let shown = ZoomTrack.view(scale: zoom.scale, x: spot.x, y: spot.y).rect
            let rect = CGRect(x: shown.minX * size.width, y: shown.minY * size.height,
                              width: shown.width * size.width, height: shown.height * size.height)
            ZStack(alignment: .topLeading) {
                if let frame {
                    Image(decorative: frame, scale: 1).resizable()
                } else {
                    Surfaces.surface
                }
                // Dims what the zoom leaves out.
                Path { path in
                    path.addRect(CGRect(origin: .zero, size: size))
                    path.addRect(rect)
                }
                .fill(Surfaces.scrim, style: FillStyle(eoFill: true))
                Rectangle()
                    .strokeBorder(Palette.accent, lineWidth: Layout.selectionRing)
                    .frame(width: rect.width, height: rect.height)
                    .offset(x: rect.minX, y: rect.minY) // grid: ok follows the zoom
            }
            .clipShape(Radius.shape(Radius.xs))
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if dragStart == nil { dragStart = editor.zooms }
                    let x = min(max(value.location.x / size.width, 0), 1)
                    let y = min(max(value.location.y / size.height, 0), 1)
                    editor.previewZooms(editor.zooms(changing: zoom.id) { $0.x = x; $0.y = y; $0.focus = .fixed })
                }
                .onEnded { _ in
                    if let start = dragStart { editor.commitZooms(from: start, named: "Zoom Focus") }
                    dragStart = nil
                })
            .pointerStyle(.grabIdle)
        }
        .aspectRatio(aspect, contentMode: .fit)
        .task(id: zoom.id) {
            frame = await editor.sourceFrame(at: (zoom.start + zoom.end) / 2, maxSize: CGSize(width: 640, height: 640))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Focus point")
        .accessibilityValue("\(Int((spot.x * 100).rounded()))% across, \(Int((spot.y * 100).rounded()))% down")
        .accessibilityAdjustableAction { direction in
            let step = direction == .increment ? 0.05 : -0.05
            editor.applyZooms(editor.zooms(changing: zoom.id) {
                $0.x = min(max(spot.x + step, 0), 1); $0.y = spot.y; $0.focus = .fixed
            }, named: "Zoom Focus")
        }
        .help("Drag to choose where the zoom looks")
    }
}
