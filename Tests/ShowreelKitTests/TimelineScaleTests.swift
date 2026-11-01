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
