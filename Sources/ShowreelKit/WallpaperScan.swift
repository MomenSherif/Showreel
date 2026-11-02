import Foundation

/// Finds the macOS wallpapers that are on this Mac at full size (S-022):
/// pictures, and the first frame of video wallpapers. Download-on-demand
/// wallpapers have only small thumbnails on disk and are left out.
public enum WallpaperScan {
    public struct Found: Equatable, Sendable {
        public var name: String
        public var url: URL
        public var isMovie: Bool { WallpaperScan.movies.contains(url.pathExtension.lowercased()) }
    }

    public struct Folders: Sendable {
        /// /System/Library/Desktop Pictures: full-size pictures at the top,
        /// and `.wallpapers/<name>/` with pictures and videos.
        public var system: URL
        /// Wallpapers macOS downloaded for this person.
        public var downloaded: URL
        /// Aerial videos macOS downloaded.
        public var aerials: URL

        public init(system: URL, downloaded: URL, aerials: URL) {
            self.system = system
            self.downloaded = downloaded
            self.aerials = aerials
        }

        public static var standard: Folders {
            let home = FileManager.default.homeDirectoryForCurrentUser
            return Folders(system: URL(fileURLWithPath: "/System/Library/Desktop Pictures"),
                           downloaded: home.appending(path: "Library/Application Support/com.apple.mobileAssetDesktop"),
                           aerials: home.appending(path: "Library/Application Support/com.apple.wallpaper/aerials/videos"))
        }
    }

    static let pictures: Set<String> = ["heic", "jpg", "jpeg", "png", "tiff"]
    static let movies: Set<String> = ["mov", "mp4"]

    /// `current` (the desktop pictures now) first, then videos, then
    /// pictures, by name; each file once.
    public static func find(in folders: Folders = .standard, current: [URL] = []) -> [Found] {
        let fm = FileManager.default
        func files(_ dir: URL) -> [URL] {
            ((try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        }
        var found: [Found] = []
        // Big pictures at the top level; "Calibrate" ones are test charts.
        found += files(folders.system).filter { isPicture($0) && !$0.lastPathComponent.hasPrefix("Calibrate") }
            .map { Found(name: name(of: $0), url: $0) }
        for folder in files(folders.system.appending(path: ".wallpapers")) {
            found += files(folder).filter { usable($0) }.map { Found(name: name(of: $0), url: $0) }
        }
        found += files(folders.downloaded).filter(isPicture).map { Found(name: name(of: $0), url: $0) }
        found += files(folders.aerials).filter(isMovie).enumerated().map { i, url in Found(name: "Aerial \(i + 1)", url: url) }

        let firsts = current.filter { usable($0) }.map { Found(name: name(of: $0), url: $0) }
        let rest = found.filter(\.isMovie) + found.filter { !$0.isMovie }
        var seen = Set<String>()
        return (firsts + rest).filter { seen.insert($0.url.standardizedFileURL.path).inserted }
    }

    /// A picture, or a landscape video; never a thumbnail or a portrait video.
    static func usable(_ url: URL) -> Bool {
        let name = url.deletingPathExtension().lastPathComponent
        if name.contains("Thumbnail") { return false }
        return isPicture(url) || (isMovie(url) && !name.hasSuffix("Portrait"))
    }

    static func isPicture(_ url: URL) -> Bool { pictures.contains(url.pathExtension.lowercased()) }
    static func isMovie(_ url: URL) -> Bool { movies.contains(url.pathExtension.lowercased()) }

    /// "Sonoma Graphic Light Landscape.mov" → "Sonoma Graphic Light".
    static func name(of url: URL) -> String {
        var name = url.deletingPathExtension().lastPathComponent
        if name.hasSuffix(" Landscape") { name = String(name.dropLast(" Landscape".count)) }
        return name
    }
}
