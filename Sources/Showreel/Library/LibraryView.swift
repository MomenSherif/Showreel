import SwiftData
import SwiftUI
import ShowreelKit

/// The Library window (S-008): every project as a card, newest first.
/// One page, so no sidebar (docs/DESIGN.md, "Library").
struct LibraryView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow
    @Environment(\.undoManager) private var undoManager
    @Query(sort: \Project.createdAt, order: .reverse) private var allProjects: [Project]
    @State private var columns = 1
    @FocusState private var gridFocused: Bool

    private var projects: [Project] {
        if model.page == .empty { return [] }
        let query = model.search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return allProjects }
        return allProjects.filter { $0.title.localizedStandardContains(query) }
    }

    var body: some View {
        @Bindable var model = model
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Library")
            .navigationSubtitle(subtitle)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("New Recording", systemImage: "record.circle") { RecordController.shared.newRecording() }
                        .help("Set up a new recording (⌘N)")
                }
            }
            .searchable(text: $model.search, placement: .toolbar, prompt: "Search projects")
            .task {
                AppServices.shared.attach(model: model, openWindow: openWindow, undo: { undoManager })
                SeedData.insertIfRequested(into: model)
                SelfTest.runIfRequested(model: model)
                Snapshot.runIfRequested(model: model, openSettings: openSettings)
                // First launch: show what access Showreel needs (S-001).
                if !SelfTest.requested, !Snapshot.isActive, !Permissions.shared.canRecord,
                   !Store.defaults.bool(forKey: "welcome.done") {
                    openWindow(id: "welcome")
                }
            }
    }

    private var subtitle: String {
        let count = model.page == .empty ? 0 : allProjects.count
        return count == 1 ? "1 project" : "\(count) projects"
    }

    @ViewBuilder
    private var content: some View {
        if allProjects.isEmpty || model.page == .empty {
            ContentUnavailableView {
                Label("No Recordings Yet", systemImage: "film.stack")
            } description: {
                Text("Record your screen, voice, and camera. Showreel adds zooms and a frame for you.")
            } actions: {
                Button("New Recording") { RecordController.shared.newRecording() }
                    .buttonStyle(.borderedProminent)
            }
        } else if projects.isEmpty {
            ContentUnavailableView.search(text: model.search)
        } else {
            grid
        }
    }

    private var grid: some View {
        // Read on the main actor; the geometry closure below is Sendable.
        let gap = Space.xl, margin = Space.margin, card = Layout.cardMinWidth
        return ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: Layout.cardMinWidth), spacing: Space.xl, alignment: .top)],
                      alignment: .leading, spacing: Space.xl) {
                ForEach(projects) { project in
                    ProjectCard(project: project, selected: model.selection == project.uuid)
                        .onTapGesture(count: 2) { open(project) }
                        .onTapGesture {
                            model.selection = project.uuid
                            gridFocused = true
                        }
                        .contextMenu { contextMenu(for: project) }
                }
            }
            .padding(Space.margin)
            .gridArea("library")
            .onGeometryChange(for: Int.self) { geometry in
                let width = geometry.size.width - 2 * margin
                return max(1, Int((width + gap) / (card + gap)))
            } action: { columns = $0 }
        }
        .focusable()
        .focusEffectDisabled()
        .focused($gridFocused)
        .onKeyPress(.leftArrow) { move(by: -1) }
        .onKeyPress(.rightArrow) { move(by: 1) }
        .onKeyPress(.upArrow) { move(by: -columns) }
        .onKeyPress(.downArrow) { move(by: columns) }
        .onKeyPress(.return) {
            guard model.renaming == nil, let project = model.selectedProject else { return .ignored }
            open(project)
            return .handled
        }
        .contentShape(Rectangle())
        .onTapGesture { model.selection = nil }
    }

    private func move(by step: Int) -> KeyPress.Result {
        guard model.renaming == nil, !projects.isEmpty else { return .ignored }
        let current = projects.firstIndex { $0.uuid == model.selection }
        let next = current.map { min(max($0 + step, 0), projects.count - 1) } ?? 0
        withMotion(Motion.select) { model.selection = projects[next].uuid }
        return .handled
    }

    private func open(_ project: Project) {
        model.selection = project.uuid
        guard !project.isSaving else { return }
        openWindow(id: "editor", value: project.uuid)
    }

    @ViewBuilder
    private func contextMenu(for project: Project) -> some View {
        Button("Open") { open(project) }
            .disabled(project.isSaving)
        Button("Rename") {
            model.selection = project.uuid
            model.renaming = project.uuid
        }
        Divider()
        Button("Show in Finder") { ProjectStore.showInFinder(project) }
        Button("Duplicate") { ProjectStore.duplicate(project, in: model, undo: undoManager) }
            .disabled(project.isSaving)
        Divider()
        Button("Move to Trash") { ProjectStore.moveToTrash(project, in: model, undo: undoManager) }
    }
}
