import SwiftUI

/// Mic chip: the device's name, a live level meter, and a device menu (S-004).
struct MicToggle: View {
    @Bindable private var recorder = RecordController.shared
    @Bindable private var devices = Devices.shared
    private var permissions = Permissions.shared

    var body: some View {
        if permissions.microphone != .allowed {
            AllowChip(title: "Allow Mic…", symbol: "mic.slash",
                      help: "Allow Showreel to record your voice") { permissions.request(.microphone) }
        } else {
            DeviceChip(isOn: $recorder.micOn,
                       symbol: ("mic.fill", "mic.slash"),
                       title: recorder.micOn ? DeviceName.short(devices.microphoneName, dropping: "Microphone") : "Mic off",
                       help: recorder.meter.silent && recorder.micOn ? "No sound detected" : "Record your voice with \(devices.microphoneName)",
                       accessibilityName: "Microphone",
                       accessibilityOn: "on, \(devices.microphoneName)",
                       meter: recorder.meter) {
                DeviceMenu(title: "Microphone", items: devices.microphones, selection: $devices.microphoneID) {
                    recorder.deviceChanged(.audio)
                }
            }
        }
    }
}

/// Camera chip with a device menu (S-005). Turning it on shows the Camera Bubble.
struct CameraToggle: View {
    @Bindable private var recorder = RecordController.shared
    @Bindable private var devices = Devices.shared
    private var permissions = Permissions.shared

    var body: some View {
        if permissions.camera != .allowed {
            AllowChip(title: "Allow Camera…", symbol: "video.slash",
                      help: "Allow Showreel to show you in a Camera Bubble") { permissions.request(.camera) }
        } else {
            DeviceChip(isOn: $recorder.cameraOn,
                       symbol: ("video.fill", "video.slash"),
                       title: recorder.cameraOn ? DeviceName.short(devices.cameraName, dropping: "Camera") : "Camera off",
                       help: "Show yourself in a Camera Bubble with \(devices.cameraName)",
                       accessibilityName: "Camera",
                       accessibilityOn: "on, \(devices.cameraName)") {
                DeviceMenu(title: "Camera", items: devices.cameras, selection: $devices.cameraID) {
                    recorder.deviceChanged(.video)
                }
            }
        }
    }
}

/// System Audio chip: no device to pick, so no menu (S-006).
struct SystemAudioToggle: View {
    @Bindable private var recorder = RecordController.shared

    var body: some View {
        DeviceChip(isOn: $recorder.systemAudioOn,
                   symbol: ("speaker.wave.2.fill", "speaker.slash"),
                   title: recorder.systemAudioOn ? "System Audio" : "System Audio off",
                   help: "Record sounds your Mac plays",
                   accessibilityName: "System Audio",
                   accessibilityOn: "on") { EmptyView() }
    }
}

/// The chip already shows what kind of device it is, so "MacBook Pro
/// Microphone" reads "MacBook Pro". The full name stays in the help tag.
enum DeviceName {
    static func short(_ name: String, dropping kind: String) -> String {
        let suffix = " " + kind
        guard name.count > suffix.count + 2, name.lowercased().hasSuffix(suffix.lowercased()) else { return name }
        return String(name.dropLast(suffix.count))
    }
}

/// One input on the Record Panel: a capsule whose left part turns the input
/// on or off and whose chevron picks the device. On, it shows a filled
/// symbol in the accent color and the device's name; off, a slashed symbol
/// and "off" in secondary text, so state never rests on color alone.
private struct DeviceChip<MenuContent: View>: View {
    @Binding var isOn: Bool
    let symbol: (on: String, off: String)
    let title: String
    let help: String
    let accessibilityName: String
    let accessibilityOn: String
    var meter: MicMeter?
    @ViewBuilder let menu: () -> MenuContent
    @State private var hovering = false

    private var hasMenu: Bool { MenuContent.self != EmptyView.self }

    var body: some View {
        HStack(spacing: 0) {
            Button {
                withMotion(Motion.quick) { isOn.toggle() }
            } label: {
                HStack(spacing: Space.sm) {
                    Image(systemName: isOn ? symbol.on : symbol.off)
                        .foregroundStyle(isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: Space.lg)
                    Text(title)
                        .foregroundStyle(isOn ? .primary : .secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: Layout.deviceNameWidth, alignment: .leading)
                        .fixedSize(horizontal: true, vertical: false)
                    if isOn, let meter { LevelMeter(meter: meter).transition(.opacity) }
                }
                .padding(.leading, Space.md)
                .padding(.trailing, hasMenu ? Space.xs : Space.md)
                .frame(height: Layout.chipHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(help)
            .accessibilityLabel(accessibilityName)
            .accessibilityValue(isOn ? accessibilityOn : "off")
            .accessibilityAddTraits(isOn ? .isSelected : [])

            if hasMenu {
                menu()
                    .padding(.trailing, Space.xs)
            }
        }
        .font(.callout.weight(.medium))
        .background(Capsule().fill(isOn ? Surfaces.selected : (hovering ? Surfaces.surfaceHover : Surfaces.surface)))
        .onHover { hovering = $0 }
        .animation(Motion.resolved(Motion.hover), value: hovering)
        .animation(Motion.resolved(Motion.quick), value: isOn)
    }
}

/// A chip that asks for access instead of turning an input on.
private struct AllowChip: View {
    let title: String
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Label {
                Text(title)
            } icon: {
                Image(systemName: symbol).foregroundStyle(Surfaces.warning)
            }
            .font(.callout.weight(.medium))
            .padding(.horizontal, Space.md)
            .frame(height: Layout.chipHeight)
            .background(Capsule().fill(hovering ? Surfaces.surfaceHover : Surfaces.surface))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

/// The chevron menu inside a chip that picks a device.
private struct DeviceMenu: View {
    let title: String
    let items: [Devices.Device]
    @Binding var selection: String?
    let changed: () -> Void

    var body: some View {
        Menu {
            Section(title) {
                if items.isEmpty { Text("No \(title)s Found") }
                Picker(title, selection: $selection) {
                    ForEach(items) { Text($0.name).tag(Optional($0.id)) }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
        } label: {
            Image(systemName: "chevron.down")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: Space.xl, height: Layout.chipHeight)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Choose a \(title.lowercased())")
        .accessibilityLabel("Choose a \(title.lowercased())")
        .onChange(of: selection) { changed() }
    }
}

/// Five bars that fill with the input level. Only this view redraws at 15 Hz.
struct LevelMeter: View {
    let meter: MicMeter
    private var level: Double { meter.level }

    var body: some View {
        HStack(spacing: 2) { // grid: ok hairline gap between meter bars
            ForEach(0..<5, id: \.self) { i in
                Capsule()
                    .fill(Double(i) / 5 < level ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary))
                    .frame(width: 3, height: Space.xs + CGFloat(i) * Space.xs / 2) // grid: ok meter bars step by 2 pt like the system input meter
            }
        }
        .frame(height: Space.lg, alignment: .bottom)
        .accessibilityElement()
        .accessibilityLabel("Input level")
        .accessibilityValue("\(Int(level * 100)) percent")
    }
}
