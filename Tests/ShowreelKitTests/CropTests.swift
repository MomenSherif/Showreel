import CoreGraphics
import Testing
@testable import ShowreelKit

@Suite("Crop")
struct CropTests {
    let crop = CropRect(x: 0.25, y: 0.2, width: 0.5, height: 0.6)

    /// S-025: clicks and zoom focus points are remapped to the cropped frame.
    @Test func pointsMapIntoTheCrop() {
        #expect(crop.map(CGPoint(x: 0.5, y: 0.5)) == CGPoint(x: 0.5, y: 0.5))
        #expect(crop.map(CGPoint(x: 0.25, y: 0.2)) == CGPoint(x: 0, y: 0))
        #expect(crop.map(CGPoint(x: 0.75, y: 0.8)) == CGPoint(x: 1, y: 1))
        // A click in the cut-away part does not show.
        #expect(crop.map(CGPoint(x: 0.1, y: 0.5)) == nil)
        // A zoom focus there is kept at the nearest edge.
        #expect(crop.mapClamped(CGPoint(x: 0.1, y: 0.5)) == CGPoint(x: 0, y: 0.5))
        #expect(CropRect.full.map(CGPoint(x: 0.3, y: 0.7)) == CGPoint(x: 0.3, y: 0.7))
    }

    @Test func pixelsAreWhole() {
        #expect(crop.pixels(of: CGSize(width: 1600, height: 1000)) == CGRect(x: 400, y: 200, width: 800, height: 600))
    }

    @Test func handlesStopAtTheEdgesAndTheMinimum() {
        let wide = CropRect.full.dragging(.topLeading, dx: -0.2, dy: 0.1)
        #expect(wide == CropRect(x: 0, y: 0.1, width: 1, height: 0.9))
        let tiny = CropRect.full.dragging(.trailing, dx: -2, dy: 0)
        #expect(abs(tiny.width - CropRect.minSide) < 1e-9)
        let moved = crop.dragging(.move, dx: 0.5, dy: -0.5)
        #expect(moved == CropRect(x: 0.5, y: 0, width: 0.5, height: 0.6))
    }
}
