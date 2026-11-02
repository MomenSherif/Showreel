import ImageIO
import SwiftUI
import UniformTypeIdentifiers
import ShowreelEngine
import ShowreelKit

/// Inspector > Background (S-022): a gradient, a color, a wallpaper, or the
/// person's own image, with a blur for pictures.
struct BackgroundSection: View {
    let editor: EditorModel
    @State private var wallpapers: [Wallpaper] = []
    @State private var choosingImage = false
    /// The style when a run of color changes began.
    @State private var changeStart: Style?
    @State private var colorCommit: Task<Void, Never>?

    private var background: Style.Background { editor.style.background }

    var body: some View {
        Form {
            PresetSection(editor: editor)

            Section("Canvas") {
                Picker("Aspect Ratio", selection: aspectBinding(editor)) {
                    ForEach(Style.Aspect.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            }

            Section("Gradient") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: Layout.swatch), spacing: Space.sm)], spacing: Space.sm) {
                    Tile(name: "None", isSelected: background == .none) {
                        Image(systemName: "nosign").foregroundStyle(.secondary)
                    } action: { set(.none, named: "No Background") }
                    ForEach(GradientPreset.all) { preset in
                        Tile(name: preset.name, isSelected: background == .gradient(preset.id)) {
                            // Content colors from the preset: they show what the video will look like.
                            LinearGradient(colors: [Color(preset.from), Color(preset.to)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
                        } action: { set(.gradient(preset.id), named: "Background Gradient") }
                    }
                }
                .padding(.vertical, Space.xs)
            }

            Section {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Space.sm), count: 3), spacing: Space.sm) {
                    ForEach(BlendPreset.all) { preset in
                        Tile(name: preset.name, isSelected: background == .blend(preset.id), size: nil) {
                            BlendThumbnail(preset: preset)
                        } action: { set(.blend(preset.id), named: "Background Blend") }
                    }
                }
                .padding(.vertical, Space.xs)
            } header: {
                Text("Blend")
            } footer: {
                Text("Soft light drawn by Showreel, sharp at any size.").foregroundStyle(.secondary)
            }

            Section("Color") {
                ColorPicker("Color", selection: colorBinding, supportsOpacity: false)
            }

            Section("Wallpaper") {
                if wallpapers.isEmpty {
                    Text("No wallpapers on this Mac").foregroundStyle(.secondary)
                } else {
                    // Three tiles a row, as wide as the inspector allows.
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Space.sm), count: 3), spacing: Space.sm) {
                        ForEach(wallpapers) { wallpaper in
                            Tile(name: wallpaper.name, isSelected: background == .wallpaper(wallpaper.url.path), size: nil) {
                                Thumbnail(url: wallpaper.url)
                            } action: { set(.wallpaper(wallpaper.url.path), named: "Background Wallpaper") }
                        }
                    }
                    .padding(.vertical, Space.xs)
                }
            }

            Section("Image") {
                LabeledContent {
                    Button("Choose Image…") { choosingImage = true }
                } label: {
                    if case .image = background { Text("Your image") } else { Text("None").foregroundStyle(.secondary) }
                }
                StyleSlider(title: "Blur", editor: editor, value: \.backgroundBlur, range: 0...1,
                            format: StyleSlider.percent, undoName: "Background Blur")
                .disabled(!showsPicture)
                .help(showsPicture ? "Blur the wallpaper or image" : "Blur works on a wallpaper or an image")
            }
        }
        .formStyle(.grouped)
        .fileImporter(isPresented: $choosingImage, allowedContentTypes: [.image]) { result in
            if case .success(let url) = result { editor.chooseBackgroundImage(url) }
        }
        .task { wallpapers = Wallpaper.available() }
    }

    private var showsPicture: Bool {
        switch background {
        case .wallpaper, .image: true
        case .none, .gradient, .blend, .color: false
        }
    }

    private func set(_ new: Style.Background, named name: String) {
        var style = editor.style
        style.background = new
        withMotion(Motion.select) { editor.applyStyle(style, named: name) }
    }

    /// The color well sends a stream of changes while the color panel is
    /// dragged. They show at once and become one undo step when they stop.
    private var colorBinding: Binding<Color> {
        Binding(get: {
            if case .color(let rgb) = background { return Color(rgb) }
            return Color(GradientPreset.all[0].from)
        }, set: { color in
            let start = changeStart ?? editor.style
            changeStart = start
            var style = editor.style
            style.background = .color(RGB(color))
            editor.previewStyle(style)
            colorCommit?.cancel()
            colorCommit = Task {
                try? await Task.sleep(for: .seconds(0.6))
                guard !Task.isCancelled else { return }
                editor.commitStyle(from: start, named: "Background Color")
                changeStart = nil
            }
        })
    }
}

/// A square swatch, or with no size a 16:10 tile as wide as its grid
/// column, with a selection ring.
private struct Tile<Content: View>: View {
    let name: String
    let isSelected: Bool
    var size: CGSize? = CGSize(width: Layout.swatch, height: Layout.swatch)
    @ViewBuilder let content: Content
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            shaped
                .background(Surfaces.surface)
                .clipShape(Radius.shape(Radius.sm))
                .overlay {
                    Radius.shape(Radius.sm)
                        .strokeBorder(isSelected ? Palette.accent : Surfaces.hairline,
                                      lineWidth: isSelected ? Layout.selectionRing : 1)
                }
        }
        .buttonStyle(.plain)
        .help(name)
        .accessibilityLabel(name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder private var shaped: some View {
        if let size {
            content.frame(width: size.width, height: size.height)
        } else {
            // The picture fills a 16:10 frame and never sets its size.
            Color.clear
                .aspectRatio(Layout.wallpaperTile.width / Layout.wallpaperTile.height, contentMode: .fit)
                .overlay { content }
        }
    }
}

/// A blend drawn by the same code as the video, small, once per preset.
private struct BlendThumbnail: View {
    let preset: BlendPreset

    var body: some View {
        if let image = BlendThumbnail.image(preset) {
            Image(decorative: image, scale: 2).resizable().scaledToFill()
        }
    }

    private static var cache: [String: CGImage] = [:]
    private static let context = CIContext(options: [.cacheIntermediates: false])

    static func image(_ preset: BlendPreset) -> CGImage? {
        if let cached = cache[preset.id] { return cached }
        let rect = CGRect(x: 0, y: 0, width: 192, height: 120) // grid: ok thumbnail pixels, 16:10
        let image = context.createCGImage(Renderer.blend(preset, canvas: rect), from: rect)
        cache[preset.id] = image
        return image
    }
}

/// A small wallpaper preview, decoded off the main thread.
private struct Thumbnail: View {
    let url: URL
    @State private var image: CGImage?

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 2).resizable().scaledToFill()
            } else {
                Surfaces.surface
            }
        }
        .task(id: url) {
            let url = url
            image = await Task.detached(priority: .utility) { PictureLoader.image(at: url, maxPixels: 160) }.value
        }
    }
}

/// The canvas's aspect ratio as a binding: each choice is one undo step.
@MainActor
func aspectBinding(_ editor: EditorModel) -> Binding<Style.Aspect> {
    Binding(get: { editor.style.aspect }, set: { aspect in
        var style = editor.style
        style.aspect = aspect
        withMotion(Motion.ui) { editor.applyStyle(style, named: "Aspect Ratio") }
    })
}

extension Color {
    /// A content color from a style (it is in the video), in sRGB.
    init(_ rgb: RGB) { self.init(.sRGB, red: rgb.r, green: rgb.g, blue: rgb.b) }
}

extension RGB {
    /// The sRGB components of a color the person picked.
    init(_ color: Color) {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .black
        self.init(Double(ns.redComponent), Double(ns.greenComponent), Double(ns.blueComponent))
    }
}
