import SwiftUI
import ShowreelKit

/// The Captions section (S-039): Generate Captions, its progress, and what it made.
struct CaptionsSection: View {
    let editor: EditorModel

    var body: some View {
        if let job = editor.captionJob {
            JobView(editor: editor, job: job)
        } else if editor.captions.captions.isEmpty {
            ContentUnavailableView {
                Label("No Captions", systemImage: InspectorSection.captions.symbol)
            } description: {
                Text("Make timed captions from your voice. It runs on this Mac.")
            } actions: {
                GenerateButton(editor: editor, title: "Generate Captions")
                    .buttonStyle(.borderedProminent)
            }
            .padding(.top, Space.section)
        } else {
            Form {
                Section {
                    LabeledContent("Lines", value: "\(editor.captions.captions.count)")
                    LabeledContent("Language", value: EditorModel.languageName(editor.captions.language))
                    LabeledContent {
                        GenerateButton(editor: editor, title: "Generate Again")
                    } label: {
                        Text("Made from your voice")
                        Text("Generating again replaces these captions.").foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
        }
    }
}

private struct GenerateButton: View {
    let editor: EditorModel
    let title: String

    var body: some View {
        Button(title, systemImage: "captions.bubble") { editor.generateCaptions() }
            .disabled(!editor.canGenerateCaptions)
            .help("Make captions from the microphone recording, on this Mac")
    }
}

/// Progress with Cancel while it runs; the reason and Try Again when it failed.
private struct JobView: View {
    let editor: EditorModel
    let job: CaptionJob

    var body: some View {
        Form {
            Section {
                if let progress = job.progress {
                    VStack(alignment: .leading, spacing: Space.sm) {
                        Text(progress.text)
                        HStack(spacing: Space.md) {
                            ProgressView(value: progress.fraction)
                                .accessibilityLabel(progress.text)
                            Button("Cancel") { job.cancel() }
                                .controlSize(.small)
                                .help("Stop making captions")
                        }
                    }
                } else if let failure = job.failure {
                    Label(failure, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                    HStack {
                        Spacer()
                        Button("Try Again") { editor.generateCaptions() }
                            .help("Make captions from the microphone recording again")
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}
