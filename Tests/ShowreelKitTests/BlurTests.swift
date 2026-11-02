import CoreGraphics
import Foundation
import Testing
import ShowreelKit

@Suite("Blur")
struct BlurTests {
    /// S-048: a blur added at the playhead lasts 3 seconds, or fits the gap.
    @Test func addFitsTheGap() throws {
        var track = BlurTrack()
        let firstAdded = track.add(at: 2, duration: 10)
        let first = try #require(firstAdded)
        #expect(first.start == 2 && first.end == 5)
        // Inside a blur there is no room.
        #expect(track.add(at: 3, duration: 10) == nil)
        // Before the next blur it moves earlier so it fits.
        let secondAdded = track.add(at: 9, duration: 10)
        let second = try #require(secondAdded)
        #expect(second.start == 7 && second.end == 10)
        // A gap of 1.5 s takes a 1.5 s blur.
        let thirdAdded = track.add(at: 5, duration: 10)
        let third = try #require(thirdAdded)
        #expect(third.start == 5 && third.end == 7)
        #expect(track.add(at: 6.9, duration: 10) == nil)
        #expect(track.regions.map(\.start) == [2, 5, 7])
    }

    /// Blurs never overlap: a move or a resize stops at the neighbor.
    @Test func dragsStopAtNeighbors() {
        let a = BlurRegion(start: 0, end: 2), b = BlurRegion(start: 4, end: 6)
        let track = BlurTrack(regions: [a, b])
        #expect(track.moving(a.id, by: 5, duration: 10).regions[0].start == 2)
        #expect(track.moving(b.id, by: 10, duration: 10).regions[1].end == 10)
        #expect(track.resizing(a.id, edge: .end, by: 5, duration: 10).regions[0].end == 4)
        #expect(track.resizing(b.id, edge: .start, by: 5, duration: 10).regions[1].start == 6 - BlurTrack.minLength)
    }

    /// The rectangle is in the recording's top-left coordinates; Core Image
    /// gets it bottom-left, in whole pixels.
    @Test func pixelRectFlipsToBottomLeft() {
        let blur = BlurRegion(start: 0, end: 1, rect: CropRect(x: 0.5, y: 0, width: 0.25, height: 0.5))
        #expect(blur.pixelRect(in: CGRect(x: 0, y: 0, width: 200, height: 100)) == CGRect(x: 100, y: 50, width: 50, height: 50))
    }

    /// Drawing on the canvas spans the two points in any direction, inside the recording.
    @Test func spanningKeepsInsideAndAMinimumSize() {
        let r = CropRect.spanning(CGPoint(x: 0.8, y: 0.9), CGPoint(x: 0.2, y: -0.5), minSide: 0.02)
        #expect(r == CropRect(x: 0.2, y: 0, width: 0.6000000000000001, height: 0.9))
        let dot = CropRect.spanning(CGPoint(x: 1, y: 1), CGPoint(x: 1, y: 1), minSide: 0.02)
        #expect(abs(dot.width - 0.02) < 1e-9 && abs(dot.x - 0.98) < 1e-9)
    }

    /// A cut shifts blurs for free: they are kept in source time.
    @Test func blursShowAcrossACut() {
        var edits = EditList(sourceDuration: 10)
        _ = edits.split(atEditTime: 4)
        _ = edits.delete(edits.segments[0].id)
        let ranges = edits.editRanges(fromSource: 3, to: 6)
        #expect(ranges == [0...2])
    }

    @Test func roundTripsAndDecodesNothingAsEmpty() {
        let track = BlurTrack(regions: [BlurRegion(start: 1, end: 2, style: .pixelate, strength: 0.3)])
        #expect(BlurTrack.decode(track.encoded()) == track)
        #expect(BlurTrack.decode(nil).regions.isEmpty)
    }
}
