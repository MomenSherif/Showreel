import SwiftUI
import ShowreelKit

/// The trailing inspector: a segmented picker of six sections, and one
/// grouped Form per section (docs/DESIGN.md, "Inspector").
struct EditorInspector: View {
    @Bindable var editor: EditorModel

    var body: some View {
        VStack(spacing: 0) {
            Picker("Section", selection: $editor.section.animation(Motion.resolved(Motion.ui))) {
                ForEach(InspectorSection.allCases) { section in
                    Label(section.title, systemImage: section.symbol)
                        .help(section.title)
                        .tag(section)
                }
            }
            .pickerStyle(.segmented)
            .labelStyle(.iconOnly)
            .labelsHidden()
            .padding(.horizontal, Space.lg)
            .padding(.vertical, Space.md)

            Text(editor.section.title)
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Space.xl)
                .accessibilityAddTraits(.isHeader)

            SectionPage(section: editor.section, editor: editor)
                .frame(maxHeight: .infinity, alignment: .top)
        }
    }
}

private struct SectionPage: View {
    let section: InspectorSection
    let editor: EditorModel

    private var project: Project { editor.project }

    var body: some View {
        switch section {
        case .background:
            BackgroundSection(editor: editor)
        case .screen:
            Form {
                Section("Recording") {
                    LabeledContent("Source", value: project.sourceName.isEmpty ? "Unknown" : project.sourceName)
                    LabeledContent("Size", value: "\(project.videoWidth) × \(project.videoHeight)")
                    LabeledContent("Length", value: TimeText.clock(editor.duration))
                }
            }
            .formStyle(.grouped)
        case .effects:
            Empty(title: "No Effects", symbol: section.symbol,
                  line: "The cursor and clicks show as they were recorded.")
        case .camera:
            if project.hasCamera {
                Form {
                    Section("Camera Bubble") {
                        LabeledContent("Size", value: ["Small", "Medium", "Large"][min(max(project.bubbleSize, 0), 2)])
                        LabeledContent("Shape", value: project.bubbleShape == BubbleStyle.Shape.roundedSquare.rawValue
                                       ? "Rounded Square" : "Circle")
                    }
                }
                .formStyle(.grouped)
            } else {
                Empty(title: "No Camera in This Recording", symbol: "person.crop.circle.badge.xmark",
                      line: "Turn on the camera for your next recording to show yourself in a bubble.")
            }
        case .captions:
            if project.hasMicrophone {
                Empty(title: "No Captions", symbol: section.symbol, line: "Captions are made from your voice.")
            } else {
                Empty(title: "No Voice Recorded", symbol: "mic.slash",
                      line: "Turn on the mic for your next recording to get captions.")
            }
        case .audio:
            if project.hasMicrophone || project.hasSystemAudio {
                Form {
                    Section("Tracks") {
                        LabeledContent("Microphone", value: project.hasMicrophone ? "Recorded" : "Off")
                        LabeledContent("System Audio", value: project.hasSystemAudio ? "Recorded" : "Off")
                    }
                }
                .formStyle(.grouped)
            } else {
                Empty(title: "No Audio in This Recording", symbol: "speaker.slash",
                      line: "Turn on the mic or system audio for your next recording.")
            }
        }
    }
}

private struct Empty: View {
    let title: String
    let symbol: String
    let line: String

    var body: some View {
        ContentUnavailableView(title, systemImage: symbol, description: Text(line))
            .padding(.top, Space.section)
    }
}
