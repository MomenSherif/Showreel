import SwiftUI
import ShowreelKit

/// The toolbar's export item (S-037): Export… when idle; while exporting, a
/// gauge that opens the progress popover. The editor stays usable.
struct ExportToolbarItem: View {
    @Bindable var editor: EditorModel

    var body: some View {
        if let run = editor.export, run.isRunning {
            Button {
                editor.showsExportPopover.toggle()
            } label: {
                ProgressView(value: run.fraction)
                    .progressViewStyle(.circular)
                    .controlSize(.small)
            }
            .help("Show export progress (\(Int(run.fraction * 100))%)")
            .accessibilityLabel("Exporting \(run.url.lastPathComponent)")
            .accessibilityValue("\(Int(run.fraction * 100)) percent")
            .popover(isPresented: $editor.showsExportPopover, arrowEdge: .bottom) {
                ExportProgressView(run: run)
            }
        } else {
            Button("Export…", systemImage: "square.and.arrow.up") { editor.showExportSheet() }
                .labelStyle(.titleOnly)
                .buttonStyle(.borderedProminent)
                .help("Export a video (⌘E)")
                .disabled(!editor.canExport)
        }
    }
}

/// "Exporting <file>", a bar, the time left, and Cancel.
struct ExportProgressView: View {
    let run: ExportRun

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text("Exporting \(run.url.lastPathComponent)")
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(run.url.path)
            ProgressView(value: run.fraction)
                .accessibilityLabel("Export progress")
            HStack(spacing: Space.md) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(ExportETA.text(secondsLeft: ExportETA.secondsLeft(
                        elapsed: context.date.timeIntervalSince(run.started), fraction: run.fraction)))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Spacer()
                Button("Cancel") { run.cancel() }
                    .help("Stop exporting and delete the unfinished file")
            }
        }
        .padding(Space.lg)
        .frame(width: Layout.exportPopoverWidth)
        .gridArea("export-progress", inset: Space.lg)
    }
}
