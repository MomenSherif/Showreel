import CoreGraphics
import Foundation
import Testing
@testable import ShowreelKit

@Suite("Recording clock")
struct RecordingClockTests {
    @Test func nothingBeforeStart() {
        var clock = RecordingClock()
        clock.begin(at: 100)
        #expect(clock.mediaTime(at: 99.9) == nil)
        #expect(clock.mediaTime(at: 100) == 0)
        #expect(clock.mediaTime(at: 101.5) == 1.5)
    }

    @Test func pausesLeaveNoGap() {
        var clock = RecordingClock()
        clock.begin(at: 10)
        clock.pause(at: 12)
        #expect(clock.mediaTime(at: 13) == nil)
        #expect(clock.elapsed(at: 20) == 2)
        clock.resume(at: 20)
        #expect(clock.mediaTime(at: 20) == 2)
        #expect(clock.mediaTime(at: 21) == 3)
        clock.pause(at: 22)
        clock.resume(at: 30)
        #expect(clock.mediaTime(at: 31) == 5)
        #expect(clock.elapsed(at: 31) == 5)
    }

    @Test func doublePauseIsIgnored() {
        var clock = RecordingClock()
        clock.begin(at: 0)
        clock.pause(at: 1)
        clock.pause(at: 5)
        clock.resume(at: 6)
        #expect(clock.mediaTime(at: 7) == 2)
    }
}

@Suite("Event log")
struct EventLogTests {
    @Test func normalizesInsideTheSource() {
        let log = EventLog(source: CGRect(x: 100, y: 50, width: 200, height: 100))
        #expect(log.normalized(CGPoint(x: 200, y: 100)) == CGPoint(x: 0.5, y: 0.5))
        #expect(log.normalized(CGPoint(x: 10, y: 10)) == nil)
    }

    @Test func roundTripsAsJSON() throws {
        var log = EventLog(source: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        log.cursor = [.init(t: 0.016, x: 0.1, y: 0.2)]
        log.clicks = [.init(t: 1.2, x: 0.5, y: 0.5, button: .left)]
        log.keys = [.init(t: 2, keyCode: 36)]
        log.cameraHidden = [.init(start: 3, end: 4)]
        let decoded = try EventLog.decode(log.encoded())
        #expect(decoded == log)
        #expect(decoded.version == EventLog.currentVersion)
    }
}

@Suite("Capture rules")
struct CaptureRuleTests {
    @Test func areaFromDragIsClampedAndOrdered() {
        let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let rect = AreaRules.rect(from: CGPoint(x: 900, y: 700), to: CGPoint(x: 1200, y: 100), in: bounds)
        #expect(rect == CGRect(x: 900, y: 100, width: 100, height: 600))
        #expect(!AreaRules.isLargeEnough(rect))
        #expect(AreaRules.sizeLabel(CGRect(x: 0, y: 0, width: 1920, height: 1080)) == "1920 × 1080")
        #expect(AreaRules.evenPixels(1081) == 1082)
    }

    @Test func deviceFallsBackToDefault() {
        #expect(DeviceChoice.pick(saved: "usb", available: ["usb", "built-in"], systemDefault: "built-in")
                == .init(id: "usb", fellBack: false))
        #expect(DeviceChoice.pick(saved: "usb", available: ["built-in"], systemDefault: "built-in")
                == .init(id: "built-in", fellBack: true))
        #expect(DeviceChoice.pick(saved: nil, available: ["a", "b"], systemDefault: nil)
                == .init(id: "a", fellBack: false))
        #expect(DeviceChoice.pick(saved: "x", available: [], systemDefault: nil)
                == .init(id: nil, fellBack: false))
    }

    @Test func timeText() {
        #expect(TimeText.clock(42.9) == "0:42")
        #expect(TimeText.clock(75) == "1:15")
        #expect(TimeText.clock(3723) == "1:02:03")
        #expect(TimeText.precise(2.66) == "0:02.6")
        #expect(TimeText.spoken(72) == "1 minute 12 seconds")
        #expect(TimeText.spoken(1) == "1 second")
    }
}
