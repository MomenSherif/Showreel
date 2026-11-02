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
