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
        .target(name: "ShowreelEngine", dependencies: ["ShowreelKit", "whisper"]),
        // whisper.cpp with Metal, for captions in Arabic and 98 more languages (S-052).
        // tools/fetch-whisper.sh puts it in Vendor/ (git-ignored, checked by
        // SHA-256); build.sh runs it and copies the framework into Contents/Frameworks.
        .binaryTarget(name: "whisper", path: "Vendor/whisper.xcframework"),
        .executableTarget(
            name: "Showreel",
            dependencies: ["ShowreelKit", "ShowreelEngine"],
            // App code runs on the main thread unless you say otherwise.
            swiftSettings: [.defaultIsolation(MainActor.self)],
            // whisper.framework sits in the bundle's Frameworks folder.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(name: "ShowreelKitTests", dependencies: ["ShowreelKit"]),
        .testTarget(name: "ShowreelEngineTests", dependencies: ["ShowreelEngine", "ShowreelKit"],
                    exclude: ["Golden"]),
    ]
)
