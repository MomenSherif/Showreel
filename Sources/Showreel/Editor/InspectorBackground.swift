import ImageIO
import SwiftUI
import UniformTypeIdentifiers
import ShowreelKit

/// Inspector > Background (S-022): a gradient, a color, a wallpaper, or the
/// person's own image, with a blur for pictures.
struct BackgroundSection: View {
    let editor: EditorModel
    @State private var wallpapers: [Wallpaper] = []
    @State private var choosingImage = false
    /// The style when a slider drag or a run of color changes began.
    @State private var changeStart: Style?
    @State private var colorCommit: Task<Void, Never>?

    private var background: Style.Background { editor.style.background }

    var body: some View {
        Form {
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

            Section("Color") {
                ColorPicker("Color", selection: colorBinding, supportsOpacity: false)
            }

            Section("Wallpaper") {
                if wallpapers.isEmpty {
                    Text("No wallpapers on this Mac").foregroundStyle(.secondary)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: Layout.wallpaperTile.width), spacing: Space.sm)], spacing: Space.sm) {
                        ForEach(wallpapers) { wallpaper in
                            Tile(name: wallpaper.name, isSelected: background == .wallpaper(wallpaper.url.path),
                                 size: Layout.wallpaperTile) {
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
                LabeledContent {
                    Slider(value: blurBinding, in: 0...1) { editing in dragging(editing, named: "Background Blur") }
                        .frame(maxWidth: .infinity)
                } label: {
                    HStack {
                        Text("Blur")
                        Spacer()
                        Text(editor.style.backgroundBlur, format: .percent.precision(.fractionLength(0)))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
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
        case .none, .gradient, .color: false
        }
    }

    private func set(_ new: Style.Background, named name: String) {
        var style = editor.style
        style.background = new
        withMotion(Motion.select) { editor.applyStyle(style, named: name) }
    }

    private var blurBinding: Binding<Double> {
        Binding(get: { editor.style.backgroundBlur }, set: { value in
            var style = editor.style
            style.backgroundBlur = value
            editor.previewStyle(style)
        })
    }

    /// A slider drag is one undo step: remember the start, commit at the end.
    private func dragging(_ editing: Bool, named name: String) {
        if editing {
            changeStart = editor.style
        } else if let start = changeStart {
            editor.commitStyle(from: start, named: name)
            changeStart = nil
        }
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

/// A square or 16:10 tile with a selection ring.
private struct Tile<Content: View>: View {
    let name: String
    let isSelected: Bool
    var size = CGSize(width: Layout.swatch, height: Layout.swatch)
    @ViewBuilder let content: Content
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            content
                .frame(width: size.width, height: size.height)
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
            image = await Task.detached(priority: .utility) {
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
                return CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: 160,
                ] as CFDictionary)
            }.value
        }
    }
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
