import Foundation
import Testing
@testable import ShowreelKit

/// The Record Shortcut and the Countdown length (S-045).
@Suite("Settings values")
struct ShortcutTests {
    @Test func showsLikeTheMenuBar() {
        #expect(Shortcut.record.display == "⌃⌥⌘R")
        #expect(Shortcut(keyCode: 1, key: "S", shift: true, command: true).display == "⇧⌘S")
        #expect(Shortcut.record.spoken == "Control Option Command R")
    }

    @Test func needsCommandOptionOrControl() {
        #expect(Shortcut.record.worksInAnyApp)
        #expect(!Shortcut(keyCode: 15, key: "r").worksInAnyApp)
        #expect(!Shortcut(keyCode: 15, key: "r", shift: true).worksInAnyApp)
        #expect(Shortcut(keyCode: 15, key: "r", option: true).worksInAnyApp)
    }

    @Test func storedShortcutRoundTrips() {
        let mine = Shortcut(keyCode: 3, key: "f", option: true, command: true)
        #expect(Shortcut.decode(mine.encoded()) == mine)
    }

    @Test func missingOrUnusableFallsBackToTheStandard() {
        #expect(Shortcut.decode(nil) == .record)
        #expect(Shortcut.decode(Data("nonsense".utf8)) == .record)
        #expect(Shortcut.decode(Shortcut(keyCode: 15, key: "r").encoded()) == .record)
    }

    @Test func countdownKeepsToItsChoices() {
        #expect(CountdownLength.resolve(nil) == 3)
        #expect(CountdownLength.resolve(0) == 0)
        #expect(CountdownLength.resolve(10) == 10)
        #expect(CountdownLength.resolve(7) == 3)
        #expect(CountdownLength.title(0) == "Off")
        #expect(CountdownLength.title(5) == "5 seconds")
    }
}
