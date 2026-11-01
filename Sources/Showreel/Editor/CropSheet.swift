import AVFoundation
import SwiftUI
import ShowreelKit

/// Crop Screen (S-025): drag the corners, edges, or middle of the frame to
/// keep part of the recording. Done applies it as one undo step.
struct CropSheet: View {
    let editor: EditorModel
    @Environment(\.dismiss) private var dismiss
    @State private var crop = CropRect.full
    @State private var dragStart: CropRect?
    @State private var frame: CGImage?

    private var source: CGSize { editor.sources?.naturalSize ?? CGSize(width: 16, height: 10) } // grid: ok aspect until the tracks load

    var body: some View {
        VStack(spacing: Space.lg) {
            Text("Crop Screen").font(.headline)
            GeometryReader { geo in
                let size = fitted(in: geo.size)
                ZStack(alignment: .topLeading) {
                    Group {
                        if let frame {
                            Image(decorative: frame, scale: 1).resizable()
                        } else {
                            Surfaces.surface.overlay { ProgressView().controlSize(.small) }
                        }
                    }
                    .frame(width: size.width, height: size.height)
                    CropOverlay(crop: crop, size: size)
                    ForEach(CropRect.Handle.allCases, id: \.self) { handle in
                        HandleView(handle: handle, crop: crop, size: size)
                            .gesture(DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    let start = dragStart ?? crop
                                    dragStart = start
                                    crop = start.dragging(handle, dx: value.translation.width / size.width,
                                                          dy: value.translation.height / size.height)
                                }
                                .onEnded { _ in dragStart = nil })
                    }
                }
                .frame(width: size.width, height: size.height)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(width: Layout.cropArea.width, height: Layout.cropArea.height)

            HStack {
                let pixels = crop.pixels(of: source)
                Text(verbatim: "\(Int(pixels.width)) × \(Int(pixels.height))")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Crop size, \(Int(pixels.width)) by \(Int(pixels.height)) pixels")
                Spacer()
                Button("Reset") { withMotion(Motion.ui) { crop = .full } }
                    .disabled(crop.isFull)
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Done") {
                    var style = editor.style
                    style.crop = crop
                    editor.applyStyle(style, named: "Crop")
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(Space.margin)
        .fitsContent()
        .noInitialFocus()
        .task {
            crop = editor.style.crop
            frame = await editor.currentSourceFrame()
        }
    }

    /// The frame's size inside the area, keeping the recording's shape.
    private func fitted(in area: CGSize) -> CGSize {
        let scale = min(area.width / source.width, area.height / source.height)
        return CGSize(width: source.width * scale, height: source.height * scale)
    }
}

/// Dims what the crop cuts away and outlines what stays.
private struct CropOverlay: View {
    let crop: CropRect
    let size: CGSize

    var body: some View {
        let rect = CGRect(x: crop.x * size.width, y: crop.y * size.height,
                          width: crop.width * size.width, height: crop.height * size.height)
        ZStack(alignment: .topLeading) {
            Path { path in
                path.addRect(CGRect(origin: .zero, size: size))
                path.addRect(rect)
            }
            .fill(Surfaces.scrim, style: FillStyle(eoFill: true))
            Rectangle()
                .strokeBorder(Surfaces.onScrim, lineWidth: 1)
                .frame(width: rect.width, height: rect.height)
                .offset(x: rect.minX, y: rect.minY) // grid: ok follows the crop
        }
        .allowsHitTesting(false)
    }
}

/// One grab point: corners and edge midpoints are small squares; `move`
/// is the whole inside of the crop.
private struct HandleView: View {
    let handle: CropRect.Handle
    let crop: CropRect
    let size: CGSize

    var body: some View {
        let rect = CGRect(x: crop.x * size.width, y: crop.y * size.height,
                          width: crop.width * size.width, height: crop.height * size.height)
        if handle == .move {
            Color.clear
                .contentShape(Rectangle())
                .frame(width: max(rect.width - Space.xxl, 1), height: max(rect.height - Space.xxl, 1))
                .offset(x: rect.minX + Space.md, y: rect.minY + Space.md) // grid: ok follows the crop
                .pointerStyle(.grabIdle)
                .accessibilityLabel("Move crop")
        } else {
            let point = position(in: rect)
            Rectangle()
                .fill(Surfaces.onScrim)
                .frame(width: Space.sm, height: Space.sm)
                .padding(Space.sm)
                .contentShape(Rectangle())
                .offset(x: point.x - Space.md, y: point.y - Space.md) // grid: ok follows the crop
                .pointerStyle(.frameResize(position: frame))
                .accessibilityLabel("Crop handle")
        }
    }

    private func position(in r: CGRect) -> CGPoint {
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

    private var frame: FrameResizePosition {
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
