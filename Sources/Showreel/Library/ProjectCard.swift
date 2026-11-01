import SwiftUI
import ShowreelKit

/// One project in the Library: thumbnail, title, and "0:42 · Today, 10:14".
struct ProjectCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undoManager
    let project: Project
    let selected: Bool
    @State private var hovering = false
    @State private var draft = ""
    @FocusState private var titleFocused: Bool

    private var renaming: Bool { model.renaming == project.uuid }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            thumbnail
                .aspectRatio(Layout.thumbnailAspect, contentMode: .fit)
                .clipShape(Radius.shape(Radius.thumbnail))
                .overlay(Radius.shape(Radius.thumbnail).strokeBorder(Surfaces.hairline, lineWidth: 1))
                .padding(Layout.selectionRing + 1)
                .overlay {
                    if selected {
                        Radius.shape(Radius.thumbnail + Layout.selectionRing + 1)
                            .strokeBorder(.tint, lineWidth: Layout.selectionRing + 1)
                    }
                }
                .shadow(color: hovering ? Surfaces.shadowHover : Surfaces.shadow, radius: hovering ? 8 : 4, y: hovering ? 4 : 2)
                .animation(Motion.resolved(Motion.hover), value: hovering)
                .onHover { hovering = $0 }
            VStack(alignment: .leading, spacing: 2) {
                title
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(.horizontal, Layout.selectionRing + 1)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(project.title), \(TimeText.spoken(project.duration)), \(dateText.lowercased())")
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
        .onChange(of: renaming) { _, now in
            if now {
                draft = project.title
                titleFocused = true
            }
        }
    }

    @ViewBuilder
    private var title: some View {
        if renaming {
            TextField("Title", text: $draft)
                .textFieldStyle(.plain)
                .font(.headline)
                .focused($titleFocused)
                .onSubmit(commitRename)
                .onExitCommand { model.renaming = nil }
                .onChange(of: titleFocused) { _, focused in if !focused && renaming { commitRename() } }
        } else {
            Text(project.title)
                .font(.headline)
                .lineLimit(2)
                .truncationMode(.tail)
                .help(project.title)
        }
    }

    private func commitRename() {
        // An empty title keeps the old one (UX block, S-010).
        if !draft.trimmingCharacters(in: .whitespaces).isEmpty {
            ProjectStore.rename(project, to: draft, undo: undoManager)
        }
        model.renaming = nil
    }

    @ViewBuilder
    private var thumbnail: some View {
        if project.isSaving {
            placeholder {
                ProgressView().controlSize(.small)
                Text("Saving…").font(.callout).foregroundStyle(.secondary)
            }
        } else if let image = ProjectStore.thumbnail(for: project.uuid) {
            Color.clear.overlay {
                Image(nsImage: image).resizable().scaledToFill()
            }
        } else if ProjectStore.filesMissing(project) {
            placeholder {
                Label("Recording files are missing", systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button("Show in Finder") { ProjectStore.showInFinder(project) }
                    .controlSize(.small)
            }
        } else {
            placeholder {
                Image(systemName: "play.rectangle").font(.title).foregroundStyle(.tertiary)
            }
        }
    }

    private func placeholder(@ViewBuilder _ content: () -> some View) -> some View {
        ZStack {
            Surfaces.surface
            VStack(spacing: Space.sm) { content() }
                .padding(Space.md)
                .multilineTextAlignment(.center)
        }
    }

    private var subtitle: String { "\(TimeText.clock(project.duration)) · \(dateText)" }

    private var dateText: String {
        let date = project.createdAt
        let time = date.formatted(date: .omitted, time: .shortened)
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today, \(time)" }
        if calendar.isDateInYesterday(date) { return "Yesterday, \(time)" }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}
