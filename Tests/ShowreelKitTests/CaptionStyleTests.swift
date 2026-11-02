import Foundation
import Testing
@testable import ShowreelKit

/// Caption styles (S-056) and saved styles (S-057).
struct CaptionStyleTests {
    @Test func stylesFromBeforeS056LoadAsTheSameLook() throws {
        func decode(_ json: String) throws -> CaptionStyle { try JSONDecoder().decode(CaptionStyle.self, from: Data(json.utf8)) }
        let dark = try decode(#"{"box":"dark","highlightsWord":true,"size":1.2,"position":"top"}"#)
        #expect(dark.hasLook(of: CaptionStyle()))
        #expect(dark.size == 1.2 && dark.position == .top)

        let none = try decode(#"{"box":"none","highlightsWord":false}"#)
        #expect(!none.showsBox && none.shadow == .soft && none.highlight == .none)

        let light = try decode(#"{"box":"light"}"#)
        #expect(light.showsBox && light.boxColor == RGB(1, 1, 1) && light.boxOpacity == 0.92)
        #expect(light.textColor == RGB(0.08, 0.08, 0.1))
    }

    @Test func everyFieldRoundTrips() throws {
        var style = CaptionStyle()
        style.position = .middle
        style.font = .family("Avenir Next")
        style.weight = .heavy
        style.textColor = RGB(hex: 0x112233)
        style.allCaps = true
        style.showsBox = false
        style.boxColor = RGB(hex: 0x445566)
        style.boxOpacity = 0.4
        style.outline = 0.6
        style.outlineColor = RGB(hex: 0x778899)
        style.shadow = .glow
        style.highlight = .karaoke
        style.highlightColor = RGB(hex: 0xAABBCC)
        let back = try JSONDecoder().decode(CaptionStyle.self, from: JSONEncoder().encode(style))
        #expect(back == style)
    }

    @Test func classicIsTheDefaultAndEveryStyleIsItsOwnLook() {
        #expect(CaptionLook.all.first?.style == CaptionStyle())
        #expect(Set(CaptionLook.all.map(\.id)).count == CaptionLook.all.count)
        for (i, a) in CaptionLook.all.enumerated() {
            for b in CaptionLook.all.dropFirst(i + 1) { #expect(!a.style.hasLook(of: b.style), "\(a.name) and \(b.name)") }
        }
    }

    @Test func pickingAStyleKeepsWhereAndHowBigCaptionsAre() {
        var mine = CaptionStyle()
        mine.size = 1.3
        mine.position = .top
        mine.isVisible = false
        let pop = CaptionLook.named("bold-pop")!.style
        let picked = mine.withLook(of: pop)
        #expect(picked.size == 1.3 && picked.position == .top && !picked.isVisible)
        #expect(picked.hasLook(of: pop) && picked.allCaps)
        #expect(SavedCaptionLooks().match(picked)?.id == "bold-pop")
        var custom = picked
        custom.outline = 0.1
        #expect(SavedCaptionLooks().match(custom) == nil)
    }

    @Test func savedStylesKeepTheirLookAndNotTheirPlacement() {
        var saved = SavedCaptionLooks()
        var style = CaptionLook.named("neon")!.style
        style.textColor = RGB(hex: 0xFF0000)
        style.size = 1.5
        style.position = .top
        let look = saved.save(style, named: "  Red Neon ")
        #expect(look.name == "Red Neon")
        #expect(look.style.size == 1 && look.style.position == .bottom && look.style.hasLook(of: style))
        #expect(saved.save(style, named: " ").name == "My Style")
        #expect(saved.match(style)?.id == look.id)

        saved.rename(look.id, to: "Hot")
        saved.rename(look.id, to: "   ")
        #expect(saved.looks.first?.name == "Hot")
        #expect(SavedCaptionLooks.decode(saved.encoded()) == saved)
        saved.delete(look.id)
        #expect(saved.looks.count == 1 && !saved.looks.contains { $0.id == look.id })
        #expect(SavedCaptionLooks.decode(Data("junk".utf8)) == SavedCaptionLooks())
    }
}
