import Foundation
import Testing
@testable import ShowreelKit

@Suite("Edit list")
struct EditListTests {
    @Test func startsUncut() {
        let list = EditList(sourceDuration: 10)
        #expect(list.isUncut)
        #expect(list.duration == 10)
        #expect(list.sourceTime(atEditTime: 4) == 4)
    }

    /// S-018: a trim is a range, not a change to the files.
    @Test func trimsAreRangesAndStayInBounds() throws {
        var list = EditList(sourceDuration: 10)
        let id = try #require(list.segments.first?.id)
        list.trimStart(id, toSource: 2)
        list.trimEnd(id, toSource: 8.5)
        #expect(list.segments.first?.start == 2 && list.segments.first?.end == 8.5)
        #expect(list.duration == 6.5)
        #expect(list.sourceTime(atEditTime: 0) == 2)
        #expect(list.sourceDuration == 10)                    // the source is untouched
        list.trimStart(id, toSource: -3)
        #expect(list.segments.first?.start == 0)
        list.trimEnd(id, toSource: 0.01)
        #expect(list.segments.first?.end == EditList.minLength)
    }

    @Test func trimsCannotOverlapTheNeighbor() throws {
        var list = EditList(sourceDuration: 10)
        let split = list.split(atEditTime: 5)
        let right = try #require(split)
        let left = list.segments[0].id
        list.trimEnd(left, toSource: 4)
        list.trimStart(right.id, toSource: 1)                 // tries to reach into the left segment
        #expect(list.segments[1].start == 4)
    }

    /// S-019: split, delete, and everything after the cut moves up.
    @Test func deletingASectionClosesTheGap() throws {
        var list = EditList(sourceDuration: 10)
        let split = list.split(atEditTime: 3)
        let middle = try #require(split)
        list.split(atEditTime: 6)
        #expect(list.segments.count == 3)
        let deleted = list.delete(middle.id)
        #expect(deleted)
        #expect(list.duration == 7)
        // A zoom or caption stored at source 8 s now plays at 5 s.
        #expect(list.editTime(atSourceTime: 8) == 5)
        // One inside the deleted section no longer plays.
        #expect(list.editTime(atSourceTime: 4) == nil)
        #expect(list.sourceTime(atEditTime: 3) == 6)
    }

    @Test func splitNeedsRoomOnBothSides() {
        var list = EditList(sourceDuration: 10)
        let early = list.split(atEditTime: 0.05), late = list.split(atEditTime: 9.95)
        #expect(early == nil && late == nil)
        #expect(list.segments.count == 1)
    }

    @Test func theLastSegmentStays() throws {
        var list = EditList(sourceDuration: 10)
        let only = try #require(list.segments.first?.id)
        let deleted = list.delete(only)
        #expect(!deleted)
    }

    @Test func savesAndLoads() throws {
        var list = EditList(sourceDuration: 10)
        list.split(atEditTime: 4)
        list.delete(list.segments[0].id)
        let loaded = EditList.decode(list.encoded(), sourceDuration: 10)
        #expect(loaded == list)
        // Nothing saved, or a broken file: the uncut recording.
        #expect(EditList.decode(nil, sourceDuration: 10).isUncut)
        #expect(EditList.decode(Data("x".utf8), sourceDuration: 10).isUncut)
        // Saved against a longer file: cut back to the file.
        #expect(EditList.decode(EditList(sourceDuration: 20).encoded(), sourceDuration: 10).duration == 10)
    }
}
