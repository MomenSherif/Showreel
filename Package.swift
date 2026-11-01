// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Showreel",
    platforms: [.macOS(.v26)],
    targets: [
        // Rules and data logic with no SwiftUI, so tests run without the app.
        .target(name: "ShowreelKit"),
        // Capture, writers, and the renderer: AVFoundation, Core Image, and
        // ScreenCaptureKit, no SwiftUI or AppKit, so `swift test` can run them.
        .target(name: "ShowreelEngine", dependencies: ["ShowreelKit"]),
        .executableTarget(
            name: "Showreel",
            dependencies: ["ShowreelKit", "ShowreelEngine"],
            // App code runs on the main thread unless you say otherwise.
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(name: "ShowreelKitTests", dependencies: ["ShowreelKit"]),
    ]
)
