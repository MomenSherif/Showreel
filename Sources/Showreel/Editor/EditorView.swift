import SwiftData
import SwiftUI
import ShowreelKit

/// One project's window (S-015): it finds the project and shows the Editor,
/// or says why it cannot.
struct EditorWindow: View {
    let id: UUID
    @Query private var projects: [Project]

    init(id: UUID) {
        self.id = id
        _projects = Query(filter: #Predicate<Project> { $0.uuid == id })
    }

    var body: some View {
        Group {
            if let project = projects.first {
                if ProjectStore.filesMissing(project) {
                    ContentUnavailableView {
                        Label("Recording Files Are Missing", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text("The project folder was moved or deleted.")
                    } actions: {
                        Button("Show in Finder") { ProjectStore.showInFinder(project) }
                    }
                    .navigationTitle(project.title)
                } else {
                    EditorView(project: project)
                }
            } else {
                ContentUnavailableView("Project Not Found", systemImage: "questionmark.square.dashed")
                    .navigationTitle("Project")
            }
        }
        .frame(minWidth: 760, minHeight: 480)
        .noInitialFocus()
    }
}

/// The Editor: canvas on top, timeline below, inspector on the trailing
/// side, and a toolbar with the title, Undo and Redo, and Export
/// (docs/DESIGN.md, "Editor").
struct EditorView: View {
    @Bindable var project: Project
    @State private var editor: EditorModel
    @Environment(\.undoManager) private var undoManager

    init(project: Project) {
        self.project = project
        _editor = State(initialValue: EditorModel(project: project))
    }

    var body: some View {
        VSplitView {
            EditorCanvas(editor: editor)
                .frame(maxWidth: .infinity, minHeight: 200, maxHeight: .infinity)
                .layoutPriority(1)
            EditorTimeline(editor: editor)
                .frame(minHeight: Layout.timelineHeight.min, idealHeight: Layout.timelineHeight.ideal)
        }
        .inspector(isPresented: $editor.showsInspector) {
            EditorInspector(editor: editor)
                .inspectorColumnWidth(min: Layout.inspectorWidth.min, ideal: Layout.inspectorWidth.ideal,
                                      max: Layout.inspectorWidth.max)
        }
        .navigationTitle($project.title)
        .navigationSubtitle(TimeText.clock(editor.duration))
        .toolbar { toolbar }
        .toolbarTitleMenu { RenameButton() }
        .focusedSceneValue(\.editor, editor)
        .task { await editor.load() }
        .onDisappear { editor.stop() }
        .onChange(of: project.title) { _, title in
            let clean = ProjectTitle.clean(title)
            if clean != title { project.title = clean }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .principal) {
            Button("Undo", systemImage: "arrow.uturn.backward") { undoManager?.undo() }
                .help("Undo (⌘Z)")
                .disabled(undoManager?.canUndo != true)
            Button("Redo", systemImage: "arrow.uturn.forward") { undoManager?.redo() }
                .help("Redo (⇧⌘Z)")
                .disabled(undoManager?.canRedo != true)
        }
        ToolbarItem(placement: .primaryAction) {
            Button("Export…", systemImage: "square.and.arrow.up") {}
                .labelStyle(.titleOnly)
                .buttonStyle(.borderedProminent)
                .help("Export a video (⌘E)")
                .disabled(true) // S-036
        }
        ToolbarItem(placement: .primaryAction) {
            Button(editor.showsInspector ? "Hide Inspector" : "Show Inspector", systemImage: "sidebar.trailing") {
                withMotion(Motion.ui) { editor.showsInspector.toggle() }
            }
            .help(editor.showsInspector ? "Hide Inspector (⌃⌘I)" : "Show Inspector (⌃⌘I)")
        }
    }
}

extension FocusedValues {
    /// The Editor in the key window, for the Playback, Clip, and View menus.
    @Entry var editor: EditorModel?
}
