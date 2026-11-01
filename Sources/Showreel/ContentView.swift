import SwiftData
import SwiftUI

/// The Library window. S-008 turns the list into a grid of project cards.
struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        NavigationSplitView {
            sidebar
        } content: {
            ProjectList(page: model.page ?? .all)
                .navigationSplitViewColumnWidth(min: 260, ideal: 320)
        } detail: {
            ProjectDetail()
        }
        .task {
            SeedData.insertIfRequested(into: model)
            SelfTest.runIfRequested(model: model)
            Snapshot.runIfRequested(model: model, openSettings: openSettings)
        }
    }

    private var sidebar: some View {
        @Bindable var model = model
        return List(LibraryPage.allCases, selection: $model.page) { page in
            Label(page.title, systemImage: page.symbol)
                .tag(page)
        }
        .navigationSplitViewColumnWidth(min: 180, ideal: 212)
    }
}

struct ProjectList: View {
    @Environment(AppModel.self) private var model
    @Query(sort: \Project.createdAt, order: .reverse) private var projects: [Project]
    let page: LibraryPage

    var body: some View {
        @Bindable var model = model
        List(projects, selection: $model.selection) { project in
            Label(project.title, systemImage: "play.rectangle")
                .tag(project.id)
        }
        .overlay {
            if projects.isEmpty {
                ContentUnavailableView(
                    "No Recordings Yet",
                    systemImage: page.symbol,
                    description: Text("Record your screen, voice, and camera. Showreel adds zooms and a frame for you.")
                )
            }
        }
        .navigationTitle("Library")
    }
}

struct ProjectDetail: View {
    @Environment(AppModel.self) private var model
    @Query private var projects: [Project]

    var body: some View {
        if let project = projects.first(where: { $0.id == model.selection }) {
            @Bindable var project = project
            Form {
                TextField("Title", text: $project.title)
                LabeledContent("Length", value: Duration.seconds(project.duration).formatted(.time(pattern: .minuteSecond)))
                LabeledContent("Recorded", value: project.createdAt.formatted(date: .abbreviated, time: .shortened))
            }
            .formStyle(.grouped)
        } else {
            ContentUnavailableView("No Selection", systemImage: "sidebar.right")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
