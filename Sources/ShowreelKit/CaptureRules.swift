import CoreGraphics
import Foundation

/// Rules for an Area source.
public enum AreaRules {
    /// The smallest area people can record.
    public static let minimumSide: CGFloat = 200

    /// A rectangle from two drag points, clamped to the display.
    public static func rect(from a: CGPoint, to b: CGPoint, in bounds: CGRect) -> CGRect {
        let raw = CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
        return raw.intersection(bounds).integral
    }

    public static func isLargeEnough(_ rect: CGRect) -> Bool {
        rect.width >= minimumSide && rect.height >= minimumSide
    }

    /// "1920 × 1080"
    public static func sizeLabel(_ rect: CGRect) -> String {
        "\(Int(rect.width)) × \(Int(rect.height))"
    }

    /// Video encoders need even pixel sizes.
    public static func evenPixels(_ value: CGFloat) -> Int {
        let n = Int(value.rounded())
        return n % 2 == 0 ? n : n + 1
    }
}

/// Which capture device to use when the saved one may be gone.
public enum DeviceChoice {
    public struct Result: Equatable, Sendable {
        public let id: String?
        /// True when the saved device is gone and the default replaced it.
        public let fellBack: Bool
    }

    public static func pick(saved: String?, available: [String], systemDefault: String?) -> Result {
        if let saved, available.contains(saved) { return Result(id: saved, fellBack: false) }
        let fallback = systemDefault.flatMap { available.contains($0) ? $0 : nil } ?? available.first
        return Result(id: fallback, fellBack: saved != nil && fallback != nil)
    }
}

/// Times as people read them.
public enum TimeText {
    /// "0:42", "1:15", "1:02:03"
    public static func clock(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    /// "0:12.4", for the transport.
    public static func precise(_ seconds: Double) -> String {
        let tenths = Int((max(0, seconds) * 10).rounded(.down))
        return "\(clock(Double(tenths / 10))).\(tenths % 10)"
    }

    /// Spoken form for VoiceOver: "1 minute 12 seconds".
    public static func spoken(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        let m = total / 60, s = total % 60
        let sec = "\(s) second\(s == 1 ? "" : "s")"
        return m == 0 ? sec : "\(m) minute\(m == 1 ? "" : "s") \(sec)"
    }
}
