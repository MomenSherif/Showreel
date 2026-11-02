import SwiftUI
import ShowreelEngine
import ShowreelKit

/// Effects (M5): how zooms move, how the cursor is drawn, and the marks at
/// clicks.
struct EffectsSection: View {
    let editor: EditorModel
    /// A color change in progress: the well sends many values; one undo step
    /// is made when they stop.
    @State private var changeStart: Style?
    @State private var colorCommit: Task<Void, Never>?
    @State private var choosingPicture = false

    var body: some View {
        Form {
            Section {
                Picker("Motion", selection: speedBinding) {
                    ForEach(ZoomSpeed.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                LabeledContent("Zooms", value: zoomCount)
            } header: {
                Text("Zoom")
            } footer: {
                Text("How fast zooms move in, out, and from one spot to the next.")
                    .foregroundStyle(.secondary)
            }
            Section {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: Layout.swatch), spacing: Space.sm)], spacing: Space.sm) {
                    Tile(name: "System", isSelected: look == .system) {
                        CursorThumbnail(look: .system)
                    } action: { setLook(.system, named: "System Cursor") }
                    Tile(name: "No Cursor", isSelected: look == .none) {
                        Image(systemName: "nosign").foregroundStyle(.secondary)
                    } action: { setLook(.none, named: "No Cursor") }
                    ForEach(CursorArt.all) { art in
                        Tile(name: art.name, isSelected: look == .art(art.id)) {
                            CursorThumbnail(look: .art(art.id))
                        } action: { setLook(.art(art.id), named: "\(art.name) Cursor") }
                    }
                    if case .picture = look {
                        Tile(name: "Your Picture", isSelected: true) {
                            CursorThumbnail(look: look, picture: editor.cursorPictureImage(look))
                        } action: {}
                    }
                }
                .padding(.vertical, Space.xs)
                LabeledContent {
                    Button("Choose Picture…") { choosingPicture = true }
                } label: {
                    if case .picture = look { Text("Your picture") } else { Text("Picture").foregroundStyle(.secondary) }
                }
                if case .picture(let name, let centered) = look {
                    Picker("Clicks At", selection: Binding(get: { centered }, set: { centered in
                        setLook(.picture(name, centered: centered), named: "Cursor Click Point")
                    })) {
                        Text("Top Left").tag(false)
                        Text("Middle").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .help("Where in the picture the click lands")
                }
                Group {
                    StyleSlider(title: "Size", editor: editor, value: \.cursorScale, range: 1...3,
                                format: Self.times, undoName: "Cursor Size")
                    StyleSlider(title: "Smoothing", editor: editor, value: \.cursorSmoothing, range: 0...1,
                                format: Self.smoothing, undoName: "Cursor Smoothing")
                    Toggle("Hide When Idle", isOn: hidesBinding)
                        .help("Fade the cursor out after it has been still for 2 seconds")
                }
                .disabled(look == .none)
            } header: {
                Text("Cursor")
            } footer: {
                Text(footer).foregroundStyle(.secondary)
            }
            .disabled(editor.sources?.events == nil)
            Section {
                Picker("Effect", selection: clickBinding) {
                    Text("None").tag(Style.ClickEffect.none)
                    Text("Ripple").tag(Style.ClickEffect.ripple)
                    Text("Ring").tag(Style.ClickEffect.ring)
                }
                .pickerStyle(.segmented)
                ColorPicker("Color", selection: colorBinding, supportsOpacity: false)
                    .disabled(editor.style.clickEffect == .none)
            } header: {
                Text("Clicks")
            } footer: {
                Text("A mark at each click, for 0.4 seconds.")
                    .foregroundStyle(.secondary)
            }
            .disabled(editor.sources?.events == nil)
        }
        .formStyle(.grouped)
        .fileImporter(isPresented: $choosingPicture, allowedContentTypes: [.image]) { result in
            if case .success(let url) = result { editor.chooseCursorPicture(url) }
        }
    }

    private var look: Style.CursorLook { editor.style.cursorLook }

    private var footer: String {
        switch look {
        case .system: "The cursor is drawn from the recording, so it stays sharp at any size."
        case .none: "The video shows no cursor. Clicks still get their marks."
        case .art(let id) where CursorArt.named(id)?.pointer != nil: "An arrow, and a pointing hand over links."
        case .art, .picture: "One cursor all the time, even over text and links."
        }
    }

    private func setLook(_ new: Style.CursorLook, named name: String) {
        var style = editor.style
        style.cursorLook = new
        withMotion(Motion.select) { editor.applyStyle(style, named: name) }
    }

    static func times(_ value: Double) -> String { String(format: "%.1f×", value) }

    static func smoothing(_ value: Double) -> String {
        switch value {
        case ..<0.01: "Off"
        case ..<0.34: "Low"
        case ..<0.67: "Medium"
        default: "High"
        }
    }

    private var clickBinding: Binding<Style.ClickEffect> {
        Binding(get: { editor.style.clickEffect }, set: { effect in
            var style = editor.style
            style.clickEffect = effect
            editor.applyStyle(style, named: "Click Effect")
        })
    }

    private var colorBinding: Binding<Color> {
        Binding(get: { Color(editor.style.clickColor) }, set: { color in
            let start = changeStart ?? editor.style
            changeStart = start
            var style = editor.style
            style.clickColor = RGB(color)
            editor.previewStyle(style)
            colorCommit?.cancel()
            colorCommit = Task {
                try? await Task.sleep(for: .seconds(0.6))
                guard !Task.isCancelled else { return }
                editor.commitStyle(from: start, named: "Click Color")
                changeStart = nil
            }
        })
    }

    private var hidesBinding: Binding<Bool> {
        Binding(get: { editor.style.cursorHidesWhenIdle }, set: { hides in
            var style = editor.style
            style.cursorHidesWhenIdle = hides
            editor.applyStyle(style, named: hides ? "Hide Idle Cursor" : "Show Idle Cursor")
        })
    }

    private var zoomCount: String {
        let n = editor.zooms.segments.count
        return n == 0 ? "None" : "\(n)"
    }

    private var speedBinding: Binding<ZoomSpeed> {
        Binding(get: { editor.style.zoomSpeed }, set: { speed in
            var style = editor.style
            style.zoomSpeed = speed
            editor.applyStyle(style, named: "Zoom Motion")
        })
    }
}

/// A cursor style, small, on its tile (S-055).
private struct CursorThumbnail: View {
    let look: Style.CursorLook
    var picture: CGImage?

    var body: some View {
        if let image = Self.image(look, picture: picture) {
            Image(decorative: image, scale: 2)
                .resizable()
                .scaledToFit()
                .padding(Space.xs)
        }
    }

    private static var cache: [String: CGImage] = [:]

    /// The system arrow without the empty margin macOS keeps around it.
    private static let systemArrow: CGImage? = {
        guard let rep = NSCursor.arrow.image.representations.max(by: { $0.pixelsHigh < $1.pixelsHigh }),
              let image = (rep as? NSBitmapImageRep)?.cgImage
                ?? NSCursor.arrow.image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let w = image.width, h = image.height
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        guard let context = CGContext(data: &bytes, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return image }
        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        var minX = w, minY = h, maxX = -1, maxY = -1
        for y in 0..<h {
            for x in 0..<w where bytes[(y * w + x) * 4 + 3] > 8 {
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX else { return image }
        return image.cropping(to: CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)) ?? image
    }()

    static func image(_ look: Style.CursorLook, picture: CGImage?) -> CGImage? {
        switch look {
        case .none:
            return nil
        case .system:
            return systemArrow
        case .art(let id):
            if let cached = cache[id] { return cached }
            let image = CursorArt.named(id)?.image(pixelsPerPoint: 3)
            cache[id] = image
            return image
        case .picture:
            return picture
        }
    }
}
