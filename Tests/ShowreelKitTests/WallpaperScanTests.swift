import Foundation
import Testing
@testable import ShowreelKit

@Suite("Wallpaper scan")
struct WallpaperScanTests {
    /// A fake Desktop Pictures folder, like macOS 26's.
    static func folders() throws -> (WallpaperScan.Folders, URL) {
        let root = FileManager.default.temporaryDirectory.appending(path: "wallpapers-\(UUID().uuidString)")
        let system = root.appending(path: "Desktop Pictures")
        let files = [
            "iMac Blue.heic", "Mac Pink.heic", "Calibrate 5120x2880.jpg", "Big Sur.madesktop",
            ".wallpapers/Sonoma Horizon/Sonoma Horizon.heic",
            ".wallpapers/Sonoma Horizon/Sonoma Horizon Thumbnail.png",
            ".wallpapers/Sonoma/Sonoma Graphic Light Landscape.mov",
            ".wallpapers/Sonoma/Sonoma Graphic Light Portrait.mov",
            ".wallpapers/Tahoe Day/Tahoe Day.mov",
        ]
        for file in files {
            let url = system.appending(path: file)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data().write(to: url)
        }
        let downloaded = root.appending(path: "mobileAssetDesktop")
        try FileManager.default.createDirectory(at: downloaded, withIntermediateDirectories: true)
        try Data().write(to: downloaded.appending(path: "Monterey Graphic.heic"))
        return (WallpaperScan.Folders(system: system, downloaded: downloaded, aerials: root.appending(path: "none")), root)
    }

    @Test func findsFullSizePicturesAndLandscapeVideos() throws {
        let (folders, root) = try Self.folders()
        defer { try? FileManager.default.removeItem(at: root) }
        let found = WallpaperScan.find(in: folders)
        #expect(found.map(\.name) == ["Sonoma Graphic Light", "Tahoe Day",
                                      "iMac Blue", "Mac Pink", "Sonoma Horizon", "Monterey Graphic"])
        #expect(found.filter(\.isMovie).count == 2)
    }

    @Test func currentDesktopComesFirstOnce() throws {
        let (folders, root) = try Self.folders()
        defer { try? FileManager.default.removeItem(at: root) }
        let current = folders.system.appending(path: "Mac Pink.heic")
        let found = WallpaperScan.find(in: folders, current: [current])
        #expect(found.first?.name == "Mac Pink")
        #expect(found.filter { $0.name == "Mac Pink" }.count == 1)
    }
}
