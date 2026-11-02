import SwiftUI

/// Showreel > Settings… (⌘,): one tab per topic, one grouped Form per tab.
/// Every change applies at once (S-045).
struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.settingsTab) {
            ForEach(SettingsTab.allCases) { tab in
                page(tab)
                    .tabItem { Label(tab.title, systemImage: tab.symbol) }
                    .tag(tab)
            }
        }
        .noInitialFocus()
    }

    @ViewBuilder
    private func page(_ tab: SettingsTab) -> some View {
        Form {
            switch tab {
            case .general: GeneralSettings()
            case .recording: RecordingSettings()
            case .export: ExportDefaults()
            case .captions: CaptionSettings()
            case .appearance: AppearanceSettings()
            }
        }
        .formStyle(.grouped)
        .fitsContent()
        .frame(width: Layout.settingsWidth)
    }
}

enum SettingsTab: String, CaseIterable, Identifiable {
    case general, recording, export, captions, appearance

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .recording: "Recording"
        case .export: "Export"
        case .captions: "Captions"
        case .appearance: "Appearance"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .recording: "record.circle"
        case .export: "square.and.arrow.up"
        case .captions: "captions.bubble"
        case .appearance: "paintpalette"
        }
    }
}

/// Where projects are kept and where exports go.
struct GeneralSettings: View {
    @Bindable private var settings = AppSettings.shared
    @State private var choosing = false

    var body: some View {
        Section {
            LabeledContent("Projects") {
                HStack(spacing: Space.sm) {
                    FolderName(url: ProjectStore.root)
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([ProjectStore.root]) }
                }
            }
            LabeledContent("Exports") {
                HStack(spacing: Space.sm) {
                    FolderName(url: settings.exportsFolder)
                    Button("Choose…") { choosing = true }
                }
            }
        } footer: {
            Text("The Export save panel opens in the Exports folder.")
                .foregroundStyle(.secondary)
        }
        .fileImporter(isPresented: $choosing, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { settings.exportsFolder = url }
        }
        .fileDialogDefaultDirectory(settings.exportsFolder)
    }
}

/// A folder as "~/Movies/Showreel", shortened in the middle, the full path on hover.
private struct FolderName: View {
    let url: URL

    var body: some View {
        let path = url.standardizedFileURL.path // no trailing slash
        Text(path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
            .lineLimit(1)
            .truncationMode(.middle)
            .foregroundStyle(.secondary)
            .help(path)
    }
}

/// The choices the Export sheet starts with (S-045). The sheet writes back
/// what was picked, so this tab always shows the last export's choices.
struct ExportDefaults: View {
    @Bindable private var settings = AppSettings.shared

    var body: some View {
        Section {
            ExportChoices(settings: $settings.exportSettings)
        } footer: {
            Text("The Export sheet starts with these, and remembers what you pick there.")
                .foregroundStyle(.secondary)
        }
    }
}
