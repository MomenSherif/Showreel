import AppKit
import ScreenCaptureKit
import SwiftUI
import ShowreelKit

/// The floating Record Panel (S-002): source, Mic, Camera, System Audio,
/// and Start Recording, on one glass bar near the top of the active display.
final class RecordPanel {
    static let shared = RecordPanel()
    private(set) var panel: FloatingPanel?

    func show(activate: Bool) {
        if panel == nil {
            var options = FloatingPanel.Options()
            options.movable = true
            options.onCancel = { RecordController.shared.closePanel() }
            panel = FloatingPanel(size: CGSize(width: Layout.recordPanel.width, height: Layout.recordPanel.height + Space.section + Space.xl),
                                  options: options, content: RecordPanelView())
        }
        guard let panel else { return }
        // Fit the bar's natural width, so no label is cut off.
        if let fitting = panel.contentView?.fittingSize, fitting.width > 0 {
            panel.setContentSize(CGSize(width: fitting.width, height: Layout.recordPanel.height + Space.section + Space.xl))
        }
        let screen = NSScreen.containing(cgRect: CGRect(origin: NSEvent.mouseLocation, size: .zero)) ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: visible.midX - panel.frame.width / 2,
                                         y: visible.maxY - panel.frame.height - Space.xl))
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
            GlassEffectContainer(spacing: Space.sm) {
                HStack(spacing: Space.sm) {
                    SourceControl()
                    Divider().frame(height: Space.xl)
                    MicToggle()
                    CameraToggle()
                    systemAudio
                    Divider().frame(height: Space.xl)
                    startButton
                    Button("Close", systemImage: "xmark") { recorder.closePanel() }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.glass)
                        .buttonBorderShape(.circle)
                        .help("Close the Record Panel (Esc)")
                }
                .padding(.horizontal, Space.md)
                .frame(height: Layout.recordPanel.height)
                .fixedSize(horizontal: true, vertical: false)
                .glassEffect(.regular, in: Capsule())
            }
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
            Spacer(minLength: 0)
        }
        .padding(.top, Space.xs)
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

    @ViewBuilder
    private var systemAudio: some View {
        Toggle(isOn: $recorder.systemAudioOn) {
            Label(recorder.systemAudioOn ? "System Audio" : "System Audio off",
                  systemImage: recorder.systemAudioOn ? "speaker.wave.2" : "speaker.slash")
        }
        .toggleStyle(.button)
        .buttonStyle(.glass)
        .help("Record sounds your Mac plays")
        .accessibilityLabel("System Audio")
        .accessibilityValue(recorder.systemAudioOn ? "on" : "off")
    }

    @ViewBuilder
    private var startButton: some View {
        if permissions.canRecord {
            Button {
                recorder.start()
            } label: {
                Label("Start Recording", systemImage: "record.circle")
                    .fontWeight(.semibold)
            }
            .buttonStyle(.glassProminent)
            .tint(Media.record)
            .keyboardShortcut(.defaultAction)
            .disabled(recorder.startBlocker != nil)
            .help(recorder.startBlocker ?? "Count down and start recording (Return)")
        } else {
            Button("Allow Screen Recording…") { Permissions.shared.request(.screen) }
                .buttonStyle(.glassProminent)
                .help("Showreel needs Screen Recording access to record")
        }
    }
}

/// Display | Window | Area, with a popover of live thumbnails (S-003).
struct SourceControl: View {
    @Bindable private var recorder = RecordController.shared
    private var picking: Bool {
        get { recorder.showingSourcePicker }
        nonmutating set { recorder.showingSourcePicker = newValue }
    }

    var body: some View {
        HStack(spacing: Space.xs) {
            Picker("Source", selection: $recorder.sourceKind) {
                ForEach(SourceKind.allCases, id: \.self) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .help("Choose what to record")
            .onChange(of: recorder.sourceKind) { _, kind in
                if kind == .window || (kind == .display && recorder.displays.count > 1) { picking = true }
            }

            Button {
                if recorder.sourceKind == .area { AreaSelector.shared.begin() } else { picking = true }
            } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .help(chevronHelp)
            .accessibilityLabel(chevronHelp)
            .popover(isPresented: $recorder.showingSourcePicker, arrowEdge: .bottom) {
                SourcePicker(kind: recorder.sourceKind) { picking = false }
            }
        }
    }

    private var chevronHelp: String {
        switch recorder.sourceKind {
        case .display: "Choose a display"
        case .window: "Choose a window"
        case .area: "Select an area again"
        }
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
                            tiles(windows.map { ($0.windowID, $0.title ?? app) }, selected: recorder.windowID) {
                                recorder.windowID = $0
                            }
                        }
                    }
                } else {
                    tiles(recorder.displays.map { ($0.displayID, DisplayNames.name(for: $0)) }, selected: recorder.displayID) {
                        recorder.displayID = $0
                    }
                }
            }
            .frame(maxHeight: 420)
        }
        .padding(Space.lg)
        .frame(width: 520)
        .task { await loadThumbnails() }
    }

    private func tiles(_ items: [(UInt32, String)], selected: UInt32?, choose: @escaping (UInt32) -> Void) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: Space.md, alignment: .top)], spacing: Space.md) {
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
