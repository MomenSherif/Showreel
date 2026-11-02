import Foundation
import Testing
@testable import ShowreelKit

@Suite("Auto zoom")
struct ZoomTests {
    private func log(clicks: [(Double, Double, Double)] = [], keys: [Double] = [],
                     caret: [(Double, Double, Double)] = [], cursor: [(Double, Double, Double)] = []) -> EventLog {
        var log = EventLog(source: CGRect(x: 0, y: 0, width: 1000, height: 800))
        log.clicks = clicks.map { .init(t: $0.0, x: $0.1, y: $0.2, button: .left) }
        log.keys = keys.map { .init(t: $0, keyCode: 0) }
        log.caret = caret.map { .init(t: $0.0, x: $0.1, y: $0.2) }
        log.cursor = cursor.map { .init(t: $0.0, x: $0.1, y: $0.2) }
        return log
    }

    /// S-030: close clicks share one zoom, at 2×.
    @Test func closeClicksMergeIntoOneZoom() throws {
        let zooms = AutoZoom.segments(from: log(clicks: [(5, 0.20, 0.20), (6.5, 0.35, 0.30), (8.8, 0.30, 0.25)]), duration: 30)
        #expect(zooms.count == 1)
        let zoom = try #require(zooms.first)
        #expect(zoom.scale == 2)
        #expect(zoom.start < 5 && zoom.end > 8.8)
        #expect(abs(zoom.x - 0.85 / 3) < 1e-9)
    }

    @Test func clicksFarApartInTimeMakeTwoZooms() {
        let zooms = AutoZoom.segments(from: log(clicks: [(5, 0.2, 0.2), (7.6, 0.2, 0.2)]), duration: 30)
        #expect(zooms.count == 2)
    }

    @Test func clicksFarApartOnScreenMakeTwoZoomsThatDoNotOverlap() {
        let zooms = AutoZoom.segments(from: log(clicks: [(5, 0.1, 0.1), (6, 0.8, 0.8)]), duration: 30)
        #expect(zooms.count == 2)
        #expect(zooms[0].end <= zooms[1].start)
        #expect(zooms[1].x == 0.8)
    }

    @Test func everyZoomIsAtLeastOneAndAHalfSeconds() {
        let zooms = AutoZoom.segments(from: log(clicks: [(0.1, 0.5, 0.5), (4, 0.1, 0.1), (4.2, 0.9, 0.9), (9.9, 0.5, 0.5)]),
                                      duration: 10)
        #expect(!zooms.isEmpty)
        for zoom in zooms {
            #expect(zoom.length >= 1.5 - 1e-9)
            #expect(zoom.start >= 0 && zoom.end <= 10)
        }
        for (a, b) in zip(zooms, zooms.dropFirst()) { #expect(a.end <= b.start) }
    }

    @Test func aRecordingShorterThanOneZoomHasNone() {
        #expect(AutoZoom.segments(from: log(clicks: [(0.5, 0.5, 0.5)]), duration: 1).isEmpty)
    }

    /// S-030: a typing burst zooms on the caret.
    @Test func typingZoomsOnTheCaret() throws {
        let keys = stride(from: 10.0, through: 13.0, by: 0.2).map { $0 }
        let zooms = AutoZoom.segments(from: log(keys: keys, caret: [(10.1, 0.7, 0.6), (12, 0.74, 0.6)]), duration: 30)
        let zoom = try #require(zooms.first)
        #expect(zooms.count == 1)
        #expect(abs(zoom.x - 0.72) < 1e-9 && zoom.y == 0.6)
        #expect(zoom.start < 10 && zoom.end > 13)
    }

    @Test func typingWithoutACaretUsesTheLastClick() throws {
        let zooms = AutoZoom.segments(from: log(clicks: [(2, 0.3, 0.4)], keys: [20, 20.3, 20.5, 20.9, 21.2]), duration: 30)
        #expect(zooms.count == 2)
        #expect(zooms[1].x == 0.3 && zooms[1].y == 0.4)
    }

    @Test func aFewKeysAreNotTyping() {
        #expect(AutoZoom.segments(from: log(keys: [5, 5.2], cursor: [(0, 0.5, 0.5)]), duration: 30).isEmpty)
    }

    @Test func theViewEasesInAndStaysInsideTheRecording() {
        let track = ZoomTrack(segments: [ZoomSegment(start: 2, end: 6, scale: 2, x: 0.95, y: 0.05)])
        #expect(track.view(at: 1) == .none)
        #expect(track.view(at: 2).scale == 1)
        let full = track.view(at: 4)
        #expect(full.scale == 2)
        #expect(full.rect == CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5))
        let half = track.view(at: 2.25).scale
        #expect(half > 1 && half < 2)
    }

    @Test func zoomsSurviveSaving() throws {
        let track = ZoomTrack(segments: [ZoomSegment(start: 1, end: 3)])
        #expect(ZoomTrack.decode(track.encoded()) == track)
        #expect(ZoomTrack.decode(nil) == nil)
    }

    @Test func oldLogsWithoutACaretStillLoad() throws {
        let json = #"{"version":1,"source":[[0,0],[100,100]],"cursor":[],"clicks":[],"keys":[],"bubble":[],"cameraHidden":[]}"#
        let log = try EventLog.decode(Data(json.utf8))
        #expect(log.caret.isEmpty)
    }

    /// A cut shows a zoom in pieces, in edit time.
    @Test func editRangesFollowTheCut() throws {
        var list = EditList(sourceDuration: 10)
        let id = try #require(list.segments.first?.id)
        list.trimStart(id, toSource: 2)
        _ = list.split(atEditTime: 3)            // source 2…5 | 5…10
        let second = try #require(list.segments.last?.id)
        list.trimStart(second, toSource: 6)      // keep 2…5 and 6…10
        #expect(list.editRanges(fromSource: 4, to: 7) == [2...3, 3...4])
        #expect(list.editRanges(fromSource: 0, to: 1).isEmpty)
    }
}

@Suite("Zoom focus")
struct ZoomFocusTests {
    /// S-031: Fixed Point and Auto look at the segment's spot; Follow Cursor
    /// at the cursor, smoothed.
    @Test func followCursorLooksAtTheCursor() {
        let cursor = CursorPath((0...100).map { EventLog.Point(t: Double($0) * 0.1, x: 0.8, y: 0.2) })
        var zoom = ZoomSegment(start: 0, end: 10, scale: 4, x: 0.3, y: 0.7)
        let track = { ZoomTrack(segments: [zoom]) }
        #expect(track().view(at: 5, cursor: cursor).rect.midX == 0.3)
        zoom.focus = .fixed
        #expect(track().view(at: 5, cursor: cursor).rect.midY == 0.7)
        zoom.focus = .followCursor
        let view = track().view(at: 5, cursor: cursor)
        #expect(abs(view.rect.midX - 0.8) < 1e-9 && abs(view.rect.midY - 0.2) < 1e-9)
        // No recorded cursor: the spot.
        #expect(track().view(at: 5).rect.midX == 0.3)
    }

    @Test func cursorIsReadBetweenSamples() throws {
        let cursor = CursorPath([.init(t: 1, x: 0, y: 0), .init(t: 2, x: 1, y: 0.5)])
        let mid = try #require(cursor.position(at: 1.5))
        #expect(mid.x == 0.5 && mid.y == 0.25)
        #expect(cursor.position(at: 0) == CGPoint(x: 0, y: 0))
        #expect(cursor.position(at: 9) == CGPoint(x: 1, y: 0.5))
        #expect(CursorPath().position(at: 1) == nil)
    }

    /// A crop moves the spot with its place on the recording.
    @Test func theSpotFollowsTheCrop() {
        let track = ZoomTrack(segments: [ZoomSegment(start: 0, end: 10, scale: 4, x: 0.25, y: 0.25)])
        let view = track.view(at: 5, crop: CropRect(x: 0, y: 0, width: 0.5, height: 0.5))
        #expect(view.rect.midX == 0.5 && view.rect.midY == 0.5)
    }
}

@Suite("Zoom editing")
struct ZoomEditingTests {
    let a = ZoomSegment(start: 2, end: 4)
    let b = ZoomSegment(start: 6, end: 8)
    var track: ZoomTrack { ZoomTrack(segments: [b, a]) }

    /// S-032: a click on an empty spot adds a 2-second zoom there.
    @Test func addsInAGapAndNotOnAZoom() throws {
        var t = track
        let first = t.add(at: 10, duration: 20)
        let added = try #require(first)
        #expect(added.start == 10 && added.end == 12)
        #expect(t.segments.map(\.start) == [2, 6, 10])
        #expect(t.add(at: 3, duration: 20) == nil)
        // A 2-second zoom does not fit before b: it starts earlier.
        let second = t.add(at: 5, duration: 20)
        let squeezed = try #require(second)
        #expect(squeezed.start == 4 && squeezed.end == 6)
        // No room left between a and b.
        #expect(t.add(at: 4.2, duration: 20) == nil)
        // Near the end of the recording it ends at the end.
        var end = ZoomTrack()
        #expect(end.add(at: 19.5, duration: 20)?.end == 20)
    }

    /// S-032: zooms cannot overlap; a drag stops at the neighbor's edge.
    @Test func movingStopsAtTheNeighbor() {
        let right = track.moving(a.id, by: 10, duration: 20)
        #expect(right.segments[0].start == 4 && right.segments[0].end == 6)
        let left = track.moving(a.id, by: -10, duration: 20)
        #expect(left.segments[0].start == 0)
        let last = track.moving(b.id, by: 30, duration: 20)
        #expect(last.segments[1].end == 20)
        #expect(last.segments[1].length == 2)
    }

    @Test func resizingStopsAtTheNeighborAndKeepsAMinimum() {
        #expect(track.resizing(a.id, edge: .end, by: 5, duration: 20).segments[0].end == 6)
        #expect(track.resizing(b.id, edge: .start, by: -5, duration: 20).segments[1].start == 4)
        #expect(track.resizing(a.id, edge: .start, by: 5, duration: 20).segments[0].start == 4 - ZoomTrack.minLength)
        #expect(track.resizing(b.id, edge: .end, by: 50, duration: 20).segments[1].end == 20)
    }
}

@Suite("Zoom motion")
struct ZoomMotionTests {
    let zoom = ZoomSegment(start: 2, end: 6, scale: 2, x: 0.3, y: 0.4)

    /// S-033: a critically damped spring eases in and never overshoots.
    @Test func zoomsEaseInWithoutOvershoot() {
        let path = ZoomPath(track: ZoomTrack(segments: [zoom]), duration: 10)
        #expect(path.view(at: 1.9) == .none)
        var last = 1.0
        for i in 0...60 {
            let scale = path.view(at: 2 + Double(i) / 60).scale
            #expect(scale >= last - 1e-12 && scale <= 2 + 1e-9)
            last = scale
        }
        #expect(path.view(at: 3.5).scale > 1.99)
        // And back out after the zoom, to rest.
        #expect(path.view(at: 6.2).scale < path.view(at: 6).scale)
        #expect(path.view(at: 9) == .none)
    }

    @Test func fasterSpeedsArriveSooner() {
        let track = ZoomTrack(segments: [zoom])
        let at = { (speed: ZoomSpeed) in ZoomPath(track: track, duration: 10, speed: speed).view(at: 2.3).scale }
        #expect(at(.slow) < at(.medium) && at(.medium) < at(.fast))
    }

    /// Zooms back to back pan from one spot to the next without zooming out.
    @Test func backToBackZoomsPanInsteadOfZoomingOut() {
        let next = ZoomSegment(start: 6, end: 10, scale: 2, x: 0.7, y: 0.4)
        let path = ZoomPath(track: ZoomTrack(segments: [zoom, next]), duration: 12)
        for i in 0...60 { #expect(path.view(at: 5.5 + Double(i) / 60).scale > 1.99) }
        #expect(path.view(at: 9.5).rect.midX > 0.69)
    }

    /// S-033: following a shaky cursor does not shake the picture.
    @Test func followingTheCursorHasNoJitter() {
        // The cursor drifts right fast enough to move the camera, with ±1%
        // noise on every 60 Hz sample.
        var noise = SystemRandomNumberGenerator()
        let points = (0..<600).map { i -> EventLog.Point in
            let t = Double(i) / 60
            return EventLog.Point(t: t, x: 0.3 + t * 0.05 + Double.random(in: -0.01...0.01, using: &noise), y: 0.5)
        }
        var follow = zoom
        follow.focus = .followCursor
        follow.scale = 4      // the most zoomed in, where shaking shows most
        let path = ZoomPath(track: ZoomTrack(segments: [follow]), cursor: CursorPath(points), duration: 10)
        let centers = stride(from: 3.0, through: 5.9, by: 1.0 / 60).map { path.view(at: $0).rect.midX }
        // Frame-to-frame changes in speed stay far below the cursor's noise.
        let jerks = zip(zip(centers, centers.dropFirst()), centers.dropFirst(2)).map { abs($0.0 - 2 * $0.1 + $1) }
        // At 4× on a 1920-pixel video, 0.0001 is under a pixel of shake.
        #expect(jerks.max() ?? 1 < 0.0001, "max \(jerks.max() ?? -1)")
        // It still follows: the cursor ends near x = 0.6, inside the view.
        let end = path.view(at: 5.9).rect
        #expect(end.minX < 0.59 && end.maxX > 0.59, "\(end)")
    }

    @Test func noZoomsMeansNoPath() {
        #expect(ZoomPath(track: ZoomTrack(), duration: 10).view(at: 3) == .none)
    }

    @Test func oldStylesGetMediumSpeed() throws {
        #expect(Style.decode(Data("{}".utf8)).zoomSpeed == .medium)
    }
}
