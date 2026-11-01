import Testing
@testable import ShowreelKit

@Suite("Timeline scale")
struct TimelineScaleTests {
    @Test func fitShowsTheWholeLength() {
        let scale = TimelineScale.fit(duration: 10, width: 800)
        #expect(scale.pointsPerSecond == 80)
        #expect(scale.x(at: 10) == 800)
        #expect(scale.seconds(at: 400) == 5)
    }

    @Test func labelsAreWholeSecondsWhenRoomy() {
        let scale = TimelineScale(pointsPerSecond: 80)
        #expect(scale.labelStep() == 1)
        #expect(scale.label(3) == "0:03")
        #expect(scale.tickStep() == 0.1)
    }

    @Test func labelsUseTenthsWhenZoomedIn() {
        let scale = TimelineScale(pointsPerSecond: 400)
        #expect(scale.labelStep() == 0.2)
        #expect(scale.label(0.4) == "0:00.4")
    }

    @Test func longRecordingsUseMinutes() {
        let scale = TimelineScale.fit(duration: 3600, width: 1000)
        #expect(scale.labelStep() == 300)
        #expect(scale.label(600) == "10:00")
        #expect(scale.tickStep() * scale.pointsPerSecond >= 8)
    }
}

@Suite("Playhead moves")
struct PlayheadMoveTests {
    @Test func stepsOneFrameOnTheGrid() {
        #expect(PlayheadMove.step(from: 1, frames: 1, duration: 10) == 61.0 / 60)
        #expect(PlayheadMove.step(from: 1.004, frames: -1, duration: 10) == 59.0 / 60)
    }

    @Test func staysInsideTheRecording() {
        #expect(PlayheadMove.step(from: 0, frames: -1, duration: 10) == 0)
        #expect(PlayheadMove.jump(from: 9.5, by: 1, duration: 10) == 10)
        #expect(PlayheadMove.jump(from: 0.4, by: -1, duration: 10) == 0)
    }
}

@Suite("Timeline zoom")
struct TimelineZoomTests {
    let fit = TimelineScale.fit(duration: 60, width: 600)   // 10 pt/s

    @Test func fitIsTheWholeRecording() {
        #expect(TimelineZoom().scale(fitting: fit) == fit)
    }

    @Test func closestShowsTenths() {
        let scale = TimelineZoom(level: 1).scale(fitting: fit)
        #expect(abs(scale.pointsPerSecond - 600) < 0.001)
        #expect(scale.labelStep() < 1)
    }

    @Test func stepsStayInRange() {
        var zoom = TimelineZoom()
        zoom.zoomOut()
        #expect(zoom.level == 0)
        for _ in 0..<20 { zoom.zoomIn() }
        #expect(zoom.level == 1)
        zoom.fit()
        #expect(zoom.isFit)
    }

    @Test func shortRecordingsCannotZoomPastClosest() {
        let short = TimelineScale.fit(duration: 0.5, width: 1000)   // 2000 pt/s already
        #expect(TimelineZoom(level: 1).scale(fitting: short) == short)
    }
}
