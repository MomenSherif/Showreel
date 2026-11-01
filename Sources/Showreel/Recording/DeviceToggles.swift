import SwiftUI

/// Mic toggle with a device menu and a live level meter (S-004).
struct MicToggle: View {
    @Bindable private var recorder = RecordController.shared
    @Bindable private var devices = Devices.shared
    private var permissions = Permissions.shared

    var body: some View {
        if permissions.microphone != .allowed {
            Button("Allow Microphone…", systemImage: "mic.slash") { permissions.request(.microphone) }
                .buttonStyle(.glass)
                .help("Allow Showreel to record your voice")
        } else {
            HStack(spacing: 2) {
                Toggle(isOn: $recorder.micOn) {
                    HStack(spacing: Space.xs) {
                        Label(recorder.micOn ? "Mic" : "Mic off", systemImage: recorder.micOn ? "mic" : "mic.slash")
                        if recorder.micOn { LevelMeter(level: recorder.micLevel) }
                    }
                }
                .toggleStyle(.button)
                .buttonStyle(.glass)
                .help(recorder.micSilent ? "No sound detected" : "Record your voice")
                .accessibilityLabel("Microphone")
                .accessibilityValue(recorder.micOn ? "on, \(devices.microphoneName)" : "off")
                DeviceMenu(title: "Microphone", items: devices.microphones, selection: $devices.microphoneID) {
                    recorder.deviceChanged(.audio)
                }
            }
        }
    }
}

/// Camera toggle with a device menu (S-005). Turning it on shows the Camera Bubble.
struct CameraToggle: View {
    @Bindable private var recorder = RecordController.shared
    @Bindable private var devices = Devices.shared
    private var permissions = Permissions.shared

    var body: some View {
        if permissions.camera != .allowed {
            Button("Allow Camera…", systemImage: "video.slash") { permissions.request(.camera) }
                .buttonStyle(.glass)
                .help("Allow Showreel to show you in a Camera Bubble")
        } else {
            HStack(spacing: 2) {
                Toggle(isOn: $recorder.cameraOn) {
                    Label(recorder.cameraOn ? "Camera" : "Camera off", systemImage: recorder.cameraOn ? "video" : "video.slash")
                }
                .toggleStyle(.button)
                .buttonStyle(.glass)
                .help("Show yourself in a Camera Bubble")
                .accessibilityLabel("Camera")
                .accessibilityValue(recorder.cameraOn ? "on, \(devices.cameraName)" : "off")
                DeviceMenu(title: "Camera", items: devices.cameras, selection: $devices.cameraID) {
                    recorder.deviceChanged(.video)
                }
            }
        }
    }
}

/// The chevron menu that picks a device.
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
        }
        .menuIndicator(.hidden)
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .fixedSize()
        .help("Choose a \(title.lowercased())")
        .accessibilityLabel("Choose a \(title.lowercased())")
        .onChange(of: selection) { changed() }
    }
}

/// Five bars that fill with the input level.
struct LevelMeter: View {
    let level: Double

    var body: some View {
        HStack(spacing: 2) { // grid: ok hairline gap between meter bars
            ForEach(0..<5, id: \.self) { i in
                Capsule()
                    .fill(Double(i) / 5 < level ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary))
                    .frame(width: 4, height: Space.xs + CGFloat(i) * Space.xs / 2) // grid: ok meter bars step by 2 pt like the system input meter
            }
        }
        .frame(height: Space.lg, alignment: .bottom)
        .accessibilityElement()
        .accessibilityLabel("Input level")
        .accessibilityValue("\(Int(level * 100)) percent")
    }
}
