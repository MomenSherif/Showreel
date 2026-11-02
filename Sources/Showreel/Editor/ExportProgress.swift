import SwiftUI
import ShowreelKit

/// The toolbar's export item (S-037, S-038): Export… when idle; while
/// exporting, a gauge. Its popover shows the progress, then the finished
/// file. The editor stays usable.
struct ExportToolbarItem: View {
    @Bindable var editor: EditorModel

    var body: some View {
        Group {
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
            } else {
                Button("Export…", systemImage: "square.and.arrow.up") { editor.showExportSheet() }
                    .labelStyle(.titleOnly)
                    .buttonStyle(.borderedProminent)
                    .help("Export a video (⌘E)")
                    .disabled(!editor.canExport)
            }
        }
        // On the item, not the gauge: the finished state shows on Export….
        .popover(isPresented: $editor.showsExportPopover, arrowEdge: .bottom) {
            if let run = editor.export {
                if run.state == .finished { ExportDoneView(run: run) } else { ExportProgressView(run: run) }
            }
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

/// A checkmark, "Exported <file>", its size, and Share…, Show in Finder, Copy.
struct ExportDoneView: View {
    let run: ExportRun

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text("Exported \(run.url.lastPathComponent)")
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(run.url.path)
                    Text(details)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            HStack(spacing: Space.sm) {
                ShareLink("Share…", item: run.url)
                    .help("Send the video with AirDrop, Mail, Messages, and more")
                Button("Show in Finder") { run.showInFinder() }
                    .help("Show the video in a Finder window")
                Button("Copy") { run.copy() }
                    .help("Copy the video to paste into a chat or a folder")
            }
        }
        .padding(Space.lg)
        .frame(width: Layout.exportPopoverWidth, alignment: .leading)
        .gridArea("export-done", inset: Space.lg)
    }

    /// "1728 × 1080 · 47.6 MB".
    private var details: String {
        let size = "\(Int(run.size.width)) × \(Int(run.size.height))"
        guard let bytes = run.fileBytes else { return size }
        return "\(size) · \(bytes.formatted(.byteCount(style: .file)))"
    }
}
