import SwiftData
import SwiftUI
import ShowreelKit

/// Settings > Recording (S-045): the Record Shortcut, the Countdown, and the
/// style new recordings start with.
struct RecordingSettings: View {
    @Environment(AppModel.self) private var model
    @Bindable private var settings = AppSettings.shared
    @Query(sort: \StylePreset.createdAt) private var presets: [StylePreset]
    @State private var problem: AppSettings.ShortcutProblem?

    var body: some View {
        Section {
            LabeledContent("Record Shortcut") {
                ShortcutField(shortcut: settings.recordShortcut) { typed in
                    problem = settings.setRecordShortcut(typed)
                }
            }
        } footer: {
            if let problem {
                Label(problem.message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            } else {
                Text("Starts and stops recording from any app.")
                    .foregroundStyle(.secondary)
            }
        }
        Section {
            Picker("Countdown", selection: $settings.countdownSeconds) {
                ForEach(CountdownLength.choices, id: \.self) { Text(CountdownLength.title($0)).tag($0) }
            }
            Picker("Style for New Recordings", selection: defaultPreset) {
                Text("None").tag(PersistentIdentifier?.none)
                if !presets.isEmpty { Divider() }
                ForEach(presets) { preset in
                    Text(preset.name).tag(Optional(preset.persistentModelID))
                }
            }
            .disabled(presets.isEmpty)
        } footer: {
            if presets.isEmpty {
                Text("Save a style as a preset in the editor to use it here.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var defaultPreset: Binding<PersistentIdentifier?> {
        Binding(get: { presets.first(where: \.isDefault)?.persistentModelID },
                set: { id in model.makeDefault(presets.first { $0.persistentModelID == id }) })
    }
}

/// A button that shows a shortcut and, when clicked, takes the next key
/// press as the new one. Escape stops without a change; Reset goes back to ⌃⌥⌘R.
struct ShortcutField: View {
    let shortcut: Shortcut
    let onChange: (Shortcut) -> Void
    @State private var monitor: Any?

    private var isListening: Bool { monitor != nil }

    var body: some View {
        HStack(spacing: Space.sm) {
            if shortcut != .record && !isListening {
                Button("Reset") { onChange(.record) }
                    .help("Use \(Shortcut.record.display) again")
            }
            Button(isListening ? "Type Shortcut…" : shortcut.display) {
                isListening ? stop() : listen()
            }
            .monospacedDigit()
            .frame(minWidth: Layout.shortcutFieldWidth)
            .help(isListening ? "Press the new keys, or Escape to keep \(shortcut.display)" : "Click, then press new keys")
            .accessibilityLabel("Record Shortcut")
            .accessibilityValue(isListening ? "Type a shortcut" : shortcut.spoken)
        }
        .onDisappear(perform: stop)
    }

    private func listen() {
        // While listening, the old shortcut must not start a recording.
        HotKeys.setRecordPaused(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let plain = event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty
            if event.keyCode == 53, plain { // Escape
                stop()
            } else {
                stop()
                onChange(Shortcut(event: event))
            }
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        HotKeys.setRecordPaused(false)
    }
}
