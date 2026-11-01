import CoreGraphics
import Testing
@testable import ShowreelKit

@Suite("Camera Bubble")
struct BubbleTests {
    let visible = CGRect(x: 0, y: 0, width: 1000, height: 800)
    let size = CGSize(width: 200, height: 200)

    @Test func eightTargetsNoCenter() {
        let targets = BubbleSnap.targets(for: size, in: visible, inset: 24)
        #expect(targets.count == 8)
        #expect(targets.contains(CGRect(x: 24, y: 24, width: 200, height: 200)))
        #expect(targets.contains(CGRect(x: 776, y: 576, width: 200, height: 200)))
        #expect(targets.contains(CGRect(x: 400, y: 24, width: 200, height: 200)))
        #expect(!targets.contains(CGRect(x: 400, y: 300, width: 200, height: 200)))
    }

    @Test func snapsWithinDistance() {
        let near = CGRect(x: 790, y: 560, width: 200, height: 200)
        #expect(BubbleSnap.snapped(near, in: visible, inset: 24, distance: 24) == CGRect(x: 776, y: 576, width: 200, height: 200))
    }

    @Test func staysWhereDroppedWhenFar() {
        let free = CGRect(x: 300, y: 200, width: 200, height: 200)
        #expect(BubbleSnap.snapped(free, in: visible, inset: 24, distance: 24) == free)
    }

    @Test func neverLeavesTheScreen() {
        let off = CGRect(x: 950, y: -100, width: 200, height: 200)
        #expect(BubbleSnap.snapped(off, in: visible, inset: 24, distance: 24) == CGRect(x: 800, y: 0, width: 200, height: 200))
    }

    @Test func centerFollowsTheLog() {
        var log = EventLog(source: .zero)
        log.bubble = [.init(t: 0, x: 0.9, y: 0.8), .init(t: 5, x: 0.1, y: 0.2)]
        #expect(log.bubbleCenter(at: 2, fallback: .zero) == CGPoint(x: 0.9, y: 0.8))
        #expect(log.bubbleCenter(at: 6, fallback: .zero) == CGPoint(x: 0.1, y: 0.2))
        #expect(EventLog(source: .zero).bubbleCenter(at: 1, fallback: CGPoint(x: 0.5, y: 0.5)) == CGPoint(x: 0.5, y: 0.5))
    }

    @Test func hiddenRanges() {
        var hidden = HiddenRanges()
        hidden.hide(at: 2)
        hidden.hide(at: 3)        // already hidden
        hidden.show(at: 4)
        hidden.show(at: 5)        // already shown
        hidden.hide(at: 8)
        hidden.close(at: 10)      // recording stops while hidden
        #expect(hidden.ranges == [.init(start: 2, end: 4), .init(start: 8, end: 10)])
        var log = EventLog(source: .zero)
        log.cameraHidden = hidden.ranges
        #expect(log.cameraIsHidden(at: 3))
        #expect(!log.cameraIsHidden(at: 4))
        #expect(log.cameraIsHidden(at: 9.9))
    }
}
