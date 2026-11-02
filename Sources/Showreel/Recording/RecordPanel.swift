import AppKit
import ScreenCaptureKit
import SwiftUI
import ShowreelKit

/// The floating Record Panel (S-002): source, Mic, Camera, System Audio,
/// and Start Recording, on one glass bar at the bottom center of the active
/// display, where the Recording Controls take its place once recording starts.
final class RecordPanel {
    static let shared = RecordPanel()
    private(set) var panel: FloatingPanel?

    func show(activate: Bool) {
        if panel == nil {
            var options = FloatingPanel.Options()
            options.movable = true
            options.onCancel = { RecordController.shared.closePanel() }
            panel = FloatingPanel(size: CGSize(width: Layout.recordPanel.width, height: Layout.recordPanel.height + Space.section + Space.xl + Space.md),
                                  options: options, content: RecordPanelView())
        }
        guard let panel else { return }
        // Fit the bar's natural width, so no label is cut off.
        if let fitting = panel.contentView?.fittingSize, fitting.width > 0 {
            panel.setContentSize(CGSize(width: fitting.width, height: Layout.recordPanel.height + Space.section + Space.xl + Space.md))
        }
        let screen = NSScreen.containing(cgRect: CGRect(origin: NSEvent.mouseLocation, size: .zero)) ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            // The bar's bottom edge sits where the Recording Controls' does.
            panel.setFrameOrigin(NSPoint(x: visible.midX - panel.frame.width / 2,
                                         y: visible.minY + Layout.controlsInset - Space.md))
        }
        panel.present(activate: activate)
    }

    func hide() { panel?.orderOut(nil) }
}

struct RecordPanelView: View {
    @Bindable private var recorder = RecordController.shared
    private var permissions = Permissions.shared
    private var devices = Devices.shared

    var body: some View {
        VStack(spacing: Space.sm) {
            Spacer(minLength: 0)
            if let message = problemText {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .symbolRenderingMode(.multicolor)
                    .padding(.horizontal, Space.lg)
                    .padding(.vertical, Space.sm)
                    .glassEffect(.regular, in: Capsule())
                    .transition(.opacity)
            }
            GlassEffectContainer(spacing: Space.sm) {
                HStack(spacing: Space.md) {
                    CloseButton { recorder.closePanel() }
                    divider
                    SourceControl()
                    divider
                    HStack(spacing: Space.sm) {
                        MicToggle()
                        CameraToggle()
                        SystemAudioToggle()
                    }
                    divider
                    startButton
                }
                .padding(.horizontal, Space.lg)
                .frame(height: Layout.recordPanel.height)
                .fixedSize(horizontal: true, vertical: false)
                .glassEffect(.regular, in: Capsule())
            }
        }
        .padding(.bottom, Space.md)
        .padding(.horizontal, Space.lg)
        .fixedSize(horizontal: true, vertical: false)
        .animation(Motion.resolved(Motion.ui), value: problemText)
        .onAppear { permissions.startWatching() }
        .onDisappear { permissions.stopWatching() }
    }

    private var problemText: String? {
        if let problem = recorder.problem { return problem }
        if devices.lostMicrophone != nil, recorder.micOn { return "\(devices.lostMicrophone!) was disconnected. Using \(devices.microphoneName)." }
        if devices.lostCamera != nil, recorder.cameraOn { return "\(devices.lostCamera!) was disconnected. Using \(devices.cameraName)." }
        if recorder.sourceKind == .window, recorder.windowGone { return "That window was closed. Choose a window." }
        if recorder.sourceKind == .area, let area = recorder.area, !AreaRules.isLargeEnough(area) { return "Area is too small." }
        return nil
    }

    private var divider: some View {
        Divider().frame(height: Space.section)
    }

    @ViewBuilder
    private var startButton: some View {
        if permissions.canRecord {
            Button {
                recorder.start()
            } label: {
                Label("Start Recording", systemImage: "record.circle.fill")
                    .font(.body.weight(.semibold))
                    .padding(.horizontal, Space.xs)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .tint(Media.record)
            .keyboardShortcut(.defaultAction)
            .disabled(recorder.startBlocker != nil)
            .help(recorder.startBlocker ?? "Count down and start recording (Return)")
        } else {
            Button("Allow Screen Recording…") { Permissions.shared.request(.screen) }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .help("Showreel needs Screen Recording access to record")
        }
    }
}

/// The quiet close button at the panel's leading edge, like the screenshot toolbar.
private struct CloseButton: View {
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: Layout.chipHeight, height: Layout.chipHeight)
                .background(Circle().fill(hovering ? Surfaces.surfaceHover : Surfaces.surface))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Motion.resolved(Motion.hover), value: hovering)
        .help("Close the Record Panel (Esc)")
        .accessibilityLabel("Close")
    }
}

/// Display, Window, and Area as icon tiles, with a popover of live
/// thumbnails (S-003). Choosing Window, or a display when there are several,
/// opens the popover; clicking the chosen tile again reopens it.
struct SourceControl: View {
    @Bindable private var recorder = RecordController.shared
    private var picking: Bool {
        get { recorder.showingSourcePicker }
        nonmutating set { recorder.showingSourcePicker = newValue }
    }

    var body: some View {
        HStack(spacing: Space.xs) {
            ForEach(Array(SourceKind.allCases.enumerated()), id: \.element) { index, kind in
                SourceTile(kind: kind, selected: recorder.sourceKind == kind, help: help(for: kind)) {
                    choose(kind)
                }
                .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
            }
        }
        .popover(isPresented: $recorder.showingSourcePicker, arrowEdge: .top) {
            SourcePicker(kind: recorder.sourceKind) { picking = false }
        }
    }

    private func choose(_ kind: SourceKind) {
        let again = recorder.sourceKind == kind
        withMotion(Motion.select) { recorder.sourceKind = kind }
        switch kind {
        case .area:
            if again { AreaSelector.shared.begin() }
        case .window:
            picking = true
        case .display:
            if again || recorder.displays.count > 1 { picking = true }
        }
    }

    private func help(for kind: SourceKind) -> String {
        let chosen = recorder.sourceKind == kind
        switch kind {
        case .display: return chosen ? "Choose a display" : "Record a whole display"
        case .window: return chosen ? "Choose a window" : "Record one window"
        case .area: return chosen ? "Select an area again" : "Record an area you drag out"
        }
    }
}

/// One source: a symbol over its name. The chosen tile gets a fill and an
/// accent symbol.
private struct SourceTile: View {
    let kind: SourceKind
    let selected: Bool
    let help: String
    let action: () -> Void
    @State private var hovering = false

    private var symbol: String {
        switch kind {
        case .display: "display"
        case .window: "macwindow"
        case .area: "rectangle.dashed"
        }
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: Space.xs) {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                    .frame(height: Space.xl)
                Text(kind.title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(selected ? .primary : .secondary)
            }
            .frame(width: Layout.sourceTile.width, height: Layout.sourceTile.height)
            .background(Radius.shape(Radius.md).fill(selected ? Surfaces.selected : (hovering ? Surfaces.surface : .clear)))
            .contentShape(Radius.shape(Radius.md))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Motion.resolved(Motion.hover), value: hovering)
        .help(help)
        .accessibilityLabel(kind.title)
        .accessibilityHint(help)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The popover grid: displays or windows with live thumbnails, grouped by app.
struct SourcePicker: View {
    let kind: SourceKind
    let done: () -> Void
    @Bindable private var recorder = RecordController.shared
    @State private var thumbnails: [UInt32: NSImage] = [:]

    private var groups: [(String, [SCWindow])] {
        let grouped = Dictionary(grouping: recorder.windows) { $0.owningApplication?.applicationName ?? "Other" }
        return grouped.sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            Text(kind == .window ? "Choose a Window" : "Choose a Display")
                .font(.headline)
            ScrollView {
                if kind == .window {
                    if recorder.windows.isEmpty {
                        ContentUnavailableView("No Windows", systemImage: "macwindow",
                                               description: Text("Open the app you want to record, then try again."))
                    }
                    VStack(alignment: .leading, spacing: Space.lg) {
                        ForEach(groups, id: \.0) { app, windows in
                            Text(app).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                            tiles(windows.map { ($0.windowID, $0.title ?? app) }, columns: windowColumns, selected: recorder.windowID) {
                                recorder.windowID = $0
                            }
                        }
                    }
                } else {
                    tiles(recorder.displays.map { ($0.displayID, DisplayNames.name(for: $0)) }, columns: displayColumns, selected: recorder.displayID) {
                        recorder.displayID = $0
                    }
                }
            }
            .frame(width: gridWidth)
            .frame(maxHeight: Layout.sourcePickerMaxHeight)
        }
        .padding(Space.lg)
        .task { await loadThumbnails() }
    }

    /// Three windows to a row.
    private var windowColumns: Int { 3 }
    /// One column per display, up to three, so one display is not lost in an empty popover.
    private var displayColumns: Int { min(max(recorder.displays.count, 1), 3) }

    private var gridWidth: CGFloat {
        let columns = CGFloat(kind == .window ? windowColumns : displayColumns)
        return columns * Layout.sourcePickerTile + (columns - 1) * Space.md
    }

    private func tiles(_ items: [(UInt32, String)], columns: Int, selected: UInt32?, choose: @escaping (UInt32) -> Void) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(Layout.sourcePickerTile), spacing: Space.md, alignment: .top), count: columns),
                  alignment: .leading, spacing: Space.md) {
            ForEach(items, id: \.0) { id, title in
                Button {
                    choose(id)
                    done()
                } label: {
                    VStack(spacing: Space.xs) {
                        ZStack {
                            Surfaces.surface
                            if let image = thumbnails[id] {
                                Image(nsImage: image).resizable().scaledToFit()
                            } else {
                                ProgressView().controlSize(.small)
                            }
                        }
                        .aspectRatio(Layout.thumbnailAspect, contentMode: .fit)
                        .clipShape(Radius.shape(Radius.sm))
                        .overlay {
                            Radius.shape(Radius.sm)
                                .strokeBorder(selected == id ? AnyShapeStyle(.tint) : AnyShapeStyle(Surfaces.hairline),
                                              lineWidth: selected == id ? Layout.selectionRing : 1)
                        }
                        Text(title)
                            .font(.callout)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(title)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(kind.title), \(title)")
                .accessibilityAddTraits(selected == id ? .isSelected : [])
            }
        }
    }

    private func loadThumbnails() async {
        await recorder.loadContent()
        // Snapshot mode never captures the person's real screens: sample frames instead.
        if Snapshot.isActive {
            let ids = kind == .window ? recorder.windows.map(\.windowID) : recorder.displays.map(\.displayID)
            for (i, id) in ids.enumerated() {
                thumbnails[id] = NSImage(cgImage: SeedData.frame(hue: 0.55 + CGFloat(i) * 0.12), size: CGSize(width: 480, height: 300))
            }
            return
        }
        let me = Bundle.main.bundleIdentifier
        if kind == .window {
            for window in recorder.windows {
                let config = SCStreamConfiguration()
                config.width = 320
                config.height = Int(320 * window.frame.height / max(window.frame.width, 1))
                config.showsCursor = false
                if let image = try? await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: window),
                                                                           configuration: config) {
                    thumbnails[window.windowID] = NSImage(cgImage: image, size: .zero)
                }
            }
        } else {
            let content = try? await SCShareableContent.current
            let mine = content?.applications.filter { $0.bundleIdentifier == me } ?? []
            for display in recorder.displays {
                let config = SCStreamConfiguration()
                config.width = 480
                config.height = Int(480 * display.frame.height / max(display.frame.width, 1))
                config.showsCursor = false
                let filter = SCContentFilter(display: display, excludingApplications: mine, exceptingWindows: [])
                if let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) {
                    thumbnails[display.displayID] = NSImage(cgImage: image, size: .zero)
                }
            }
        }
    }
}
