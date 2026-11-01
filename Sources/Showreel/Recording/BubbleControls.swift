import AppKit
import SwiftUI

/// The Camera Bubble's size and shape (S-013), remembered for the next recording.
@Observable
final class BubbleStyle {
    static let shared = BubbleStyle()

    enum Shape: String, CaseIterable, Identifiable {
        case circle, roundedSquare
        var id: String { rawValue }
        var title: String { self == .circle ? "Circle" : "Rounded Square" }
        var symbol: String { self == .circle ? "circle" : "square" }
    }

    static let sizeNames = ["Small", "Medium", "Large"]

    /// 0 Small, 1 Medium, 2 Large (`Layout.bubbleSizes`).
    var size: Int = min(max(UserDefaults.standard.object(forKey: "bubble.size") as? Int ?? 1, 0), 2) {
        didSet {
            UserDefaults.standard.set(size, forKey: "bubble.size")
            if size != oldValue { CameraBubble.shared.styleChanged() }
        }
    }

    var shape: Shape = Shape(rawValue: UserDefaults.standard.string(forKey: "bubble.shape") ?? "") ?? .circle {
        didSet { UserDefaults.standard.set(shape.rawValue, forKey: "bubble.shape") }
    }

    var diameter: CGFloat { Layout.bubbleSizes[size] }

    /// The clip shape at `diameter`.
    func clip(_ diameter: CGFloat) -> AnyShape {
        switch shape {
        case .circle: AnyShape(Circle())
        case .roundedSquare: AnyShape(RoundedRectangle(cornerRadius: diameter * Radius.bubbleSquareRatio, style: .continuous))
        }
    }
}

/// The glass capsule that fades in under the bubble on hover: S M L and
/// the shape. It lives in a child window, so it moves with the bubble.
struct BubbleControlsView: View {
    @Bindable private var style = BubbleStyle.shared

    var body: some View {
        GlassEffectContainer(spacing: Space.xs) {
            HStack(spacing: Space.sm) {
                Picker("Size", selection: $style.size) {
                    ForEach(0..<3, id: \.self) { i in
                        Text(String(BubbleStyle.sizeNames[i].prefix(1)))
                            .accessibilityLabel(BubbleStyle.sizeNames[i])
                            .tag(i)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .help("Choose the Camera Bubble's size")
                Divider().frame(height: Space.lg)
                ForEach(BubbleStyle.Shape.allCases) { shape in
                    Button(shape.title, systemImage: style.shape == shape ? "\(shape.symbol).fill" : shape.symbol) {
                        withMotion(Motion.quick) { style.shape = shape }
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .help("Make the Camera Bubble a \(shape.title.lowercased())")
                    .accessibilityAddTraits(style.shape == shape ? .isSelected : [])
                }
            }
            .controlSize(.small)
            .padding(.horizontal, Space.sm)
            .padding(.vertical, Space.xs)
            .glassEffect(.regular, in: Capsule())
        }
        .frame(width: Layout.bubbleControls.width, height: Layout.bubbleControls.height)
        .onHover { CameraBubble.shared.hovering($0) }
    }
}
