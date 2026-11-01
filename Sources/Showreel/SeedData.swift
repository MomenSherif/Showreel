import Foundation
import SwiftData

/// Sample data for snapshots: APP_SEED=1 with APP_STORE in /tmp fills an empty
/// store with the projects named in docs/STORIES.md. Seed only what a person
/// can create in the app, or the snapshots show features no one can use.
@MainActor
enum SeedData {
    static func insertIfRequested(into model: AppModel) {
        guard ProcessInfo.processInfo.environment["APP_SEED"] == "1" else { return }
        guard Store.isOverridden else {
            print("APP_SEED ignored: APP_STORE must be a file in /tmp")
            return
        }
        let context = model.container.mainContext
        guard ((try? context.fetchCount(FetchDescriptor<Project>())) ?? 0) == 0 else { return }
        let samples: [(String, Double)] = [
            ("Onboarding walkthrough", 42),
            ("Pricing page tour", 75),
            ("API keys demo", 28),
        ]
        for (index, sample) in samples.enumerated() {
            let project = Project(title: sample.0, duration: sample.1)
            project.createdAt = Date.now.addingTimeInterval(Double(-index) * 86_400)
            context.insert(project)
        }
        try? context.save()
    }
}
