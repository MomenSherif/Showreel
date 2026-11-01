import AppKit
import SwiftUI
import ShowreelKit

/// Area mode (S-003): dims every display and lets people drag out the area
/// to record. Return confirms, Escape goes back to the previous source.
final class AreaSelector {
    static let shared = AreaSelector()
    private var panels: [FloatingPanel] = []
    private var previous: SourceKind = .display

    var isActive: Bool { !panels.isEmpty }
    /// The overlay on the main display (snapshot mode captures it).
    var mainPanel: NSWindow? { panels.first }

    func begin() {
        guard panels.isEmpty else { return }
        previous = RecordController.shared.sourceKind == .area ? .display : RecordController.shared.sourceKind
        RecordPanel.shared.hide()
        for screen in NSScreen.screens {
            var options = FloatingPanel.Options()
            options.level = .screenSaver
            options.onCancel = { AreaSelector.shared.cancel() }
            let panel = FloatingPanel(size: screen.frame.size, options: options,
                                      content: AreaSelectorView(screenFrame: screen.cgFrame))
            panel.setFrame(screen.frame, display: true)
            panels.append(panel)
            panel.present(activate: true)
        }
    }

    /// Return: keeps the area and brings the Record Panel back.
    func confirm() {
        close()
        RecordPanel.shared.show(activate: true)
    }

    /// Escape: back to the source chosen before.
    func cancel() {
        guard isActive else { return }
        close()
        let recorder = RecordController.shared
        if recorder.area == nil { recorder.sourceKind = previous }
        if recorder.state == .panel { RecordPanel.shared.show(activate: true) }
    }

    /// Hides the overlay when recording starts.
    func hideOverlay() { close() }

    private func close() {
        panels.forEach { $0.orderOut(nil) }
        panels = []
    }
}

struct AreaSelectorView: View {
    /// This screen's frame in global top-left points.
    let screenFrame: CGRect
    @Bindable private var recorder = RecordController.shared
    @State private var dragStart: CGPoint?
    @State private var dragMode: Mode = .draw
    @State private var original: CGRect = .zero
    @FocusState private var focused: Bool

    private enum Mode { case draw, move, resize(Corner) }
    private enum Corner { case topLeft, topRight, bottomLeft, bottomRight }

    /// The area in this screen's local coordinates, when it is on this screen.
    private var local: CGRect? {
        guard let area = recorder.area, screenFrame.intersects(area) else { return nil }
        return area.offsetBy(dx: -screenFrame.minX, dy: -screenFrame.minY)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Surfaces.scrim
                .mask {
                    Rectangle().overlay {
                        if let local {
                            Rectangle().frame(width: local.width, height: local.height)
                                .position(x: local.midX, y: local.midY) // grid: ok follows the person's drag
                                .blendMode(.destinationOut)
                        }
                    }
                    .compositingGroup()
                }
            if let local {
                Rectangle()
                    .strokeBorder(Surfaces.onScrim, style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
                    .frame(width: local.width, height: local.height)
                    .position(x: local.midX, y: local.midY) // grid: ok follows the person's drag
                ForEach(corners(of: local), id: \.0) { _, point in
                    Circle().fill(Surfaces.onScrim).frame(width: Space.md, height: Space.md)
                        .position(point) // grid: ok on the selection's corner
                }
                Text(AreaRules.sizeLabel(recorder.area!))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(Surfaces.onScrim)
                    .padding(.horizontal, Space.sm)
                    .padding(.vertical, Space.xs)
                    .background(Surfaces.scrim, in: Capsule())
                    .position(x: local.midX, y: max(Space.xl, local.minY - Space.lg)) // grid: ok above the selection
            }
            hint
        }
        .frame(width: screenFrame.width, height: screenFrame.height)
        .contentShape(Rectangle())
        .gesture(drag)
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onAppear { focused = true }
        .onKeyPress(.return) { AreaSelector.shared.confirm(); return .handled }
        .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow]) { press in
            nudge(press.key, by: press.modifiers.contains(.shift) ? 10 : 1)
            return .handled
        }
        .accessibilityLabel("Area selection")
        .accessibilityValue(recorder.area.map(AreaRules.sizeLabel) ?? "none")
    }

    private var hint: some View {
        Text("Drag to select an area. Press Return to confirm, Escape to cancel.")
            .font(.callout)
            .foregroundStyle(Surfaces.onScrim)
            .padding(.horizontal, Space.lg)
            .padding(.vertical, Space.sm)
            .background(Surfaces.scrim, in: Capsule())
            .frame(maxWidth: .infinity)
            .padding(.top, Space.section * 2)
    }

    private func corners(of r: CGRect) -> [(Int, CGPoint)] {
        [(0, CGPoint(x: r.minX, y: r.minY)), (1, CGPoint(x: r.maxX, y: r.minY)),
         (2, CGPoint(x: r.minX, y: r.maxY)), (3, CGPoint(x: r.maxX, y: r.maxY))]
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                let start = value.startLocation, now = value.location
                if dragStart == nil {
                    dragStart = start
                    original = local ?? .zero
                    dragMode = mode(at: start)
                }
                let bounds = CGRect(origin: .zero, size: screenFrame.size)
                var rect: CGRect
                switch dragMode {
                case .draw:
                    rect = AreaRules.rect(from: start, to: now, in: bounds)
                case .move:
                    rect = original.offsetBy(dx: now.x - start.x, dy: now.y - start.y)
                    rect.origin.x = min(max(rect.minX, 0), bounds.width - rect.width)
                    rect.origin.y = min(max(rect.minY, 0), bounds.height - rect.height)
                case .resize(let corner):
                    let fixed: CGPoint = switch corner {
                    case .topLeft: CGPoint(x: original.maxX, y: original.maxY)
                    case .topRight: CGPoint(x: original.minX, y: original.maxY)
                    case .bottomLeft: CGPoint(x: original.maxX, y: original.minY)
                    case .bottomRight: CGPoint(x: original.minX, y: original.minY)
                    }
                    rect = AreaRules.rect(from: fixed, to: now, in: bounds)
                }
                recorder.area = rect.offsetBy(dx: screenFrame.minX, dy: screenFrame.minY)
            }
            .onEnded { _ in dragStart = nil }
    }

    private func mode(at point: CGPoint) -> Mode {
        guard let local else { return .draw }
        let grab: CGFloat = 12
        let list: [(Corner, CGPoint)] = [(.topLeft, CGPoint(x: local.minX, y: local.minY)),
                                         (.topRight, CGPoint(x: local.maxX, y: local.minY)),
                                         (.bottomLeft, CGPoint(x: local.minX, y: local.maxY)),
                                         (.bottomRight, CGPoint(x: local.maxX, y: local.maxY))]
        if let hit = list.first(where: { hypot($0.1.x - point.x, $0.1.y - point.y) <= grab }) { return .resize(hit.0) }
        return local.contains(point) ? .move : .draw
    }

    private func nudge(_ key: KeyEquivalent, by step: CGFloat) {
        guard var area = recorder.area else { return }
        switch key {
        case .leftArrow: area.origin.x -= step
        case .rightArrow: area.origin.x += step
        case .upArrow: area.origin.y -= step
        default: area.origin.y += step
        }
        recorder.area = area
    }
}
