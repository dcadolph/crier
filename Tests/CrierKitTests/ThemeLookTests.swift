import Foundation
import Testing

@testable import CrierKit

// ThemeLookTests covers reading a theme switcher's message and drawing the reader's settings under it.
struct ThemeLookTests {
    // look is a theme look with a ticker color and no backing.
    private let look = ThemeLook(
        ticker: StoredColor(hex: "#F2D16B"), background: StoredColor(hex: "#06101C")!,
        text: StoredColor(hex: "#D8FFFA")!, accent: StoredColor(hex: "#30D159")!)

    // messageRoundTrips reads back exactly the look it was written from, with and without a ticker color and a
    // backing.
    @Test func messageRoundTrips() {
        #expect(look.message == "#F2D16B none #06101C #D8FFFA #30D159")
        #expect(ThemeLookMessage(look.message) == .set(look))
        var auto = look
        auto.ticker = nil
        #expect(auto.message == "auto none #06101C #D8FFFA #30D159")
        #expect(ThemeLookMessage(auto.message) == .set(auto))
        var pill = look
        pill.tickerBacking = StoredColor(hex: "#000000")
        #expect(pill.message == "#F2D16B #000000 #06101C #D8FFFA #30D159")
        #expect(ThemeLookMessage(pill.message) == .set(pill))
    }

    // backingReadsFromTheSecondWord takes the second word as the ticker's backing and leaves the band alone.
    @Test func backingReadsFromTheSecondWord() {
        guard case .set(let read) = ThemeLookMessage("#5FE0F5 #000000 #06101C #D8FFFA #30D159") else {
            Issue.record("message not read")
            return
        }
        #expect(read.ticker?.hex == "#5FE0F5")
        #expect(read.tickerBacking?.hex == "#000000")
        #expect(read.background.hex == "#06101C")
        #expect(read.accent.hex == "#30D159")
    }

    // emptyClears puts back the reader's own colors on an empty message.
    @Test func emptyClears() {
        #expect(ThemeLookMessage("") == .clear)
        #expect(ThemeLookMessage("   ") == .clear)
        #expect(ThemeLookMessage("").updating(look) == nil)
    }

    // junkChangesNothing keeps the held look for any message it cannot read.
    @Test func junkChangesNothing() {
        let junk = [
            "#F2D16B", "#F2D16B none #06101C #D8FFFA", "#F2D16B #06101C #D8FFFA #30D159",
            "#F2D16B none #06101C #D8FFFA #30D159 #FFFFFF", "red none #06101C #D8FFFA #30D159",
            "#F2D16B none #06101C #D8FFFA auto", "#F2D16B none #06101C #D8FFFA #30D15",
            "#F2D16B none #06101C #D8FFFA #GGGGGG", "AUTO none #06101C #D8FFFA #30D159",
            "#F2D16B black #06101C #D8FFFA #30D159", "#F2D16B NONE #06101C #D8FFFA #30D159",
            "#F2D16B #00000 #06101C #D8FFFA #30D159", "#F2D16B auto #06101C #D8FFFA #30D159",
        ]
        for message in junk {
            #expect(ThemeLookMessage(message) == .junk, "\(message)")
            #expect(ThemeLookMessage(message).updating(look) == look, "\(message)")
        }
    }

    // appliedLeavesTheReaderAlone draws the theme over the reader's settings without changing anything else,
    // and draws the reader's own settings when no look is held.
    @Test func appliedLeavesTheReaderAlone() {
        var mine = CrierKit.Settings()
        mine.look = .paper
        mine.tickerColor = StoredColor(hex: "#112233")
        mine.speed = 2
        let drawn = mine.drawn(with: look)
        #expect(drawn.look == .custom)
        #expect(drawn.tickerColor == look.ticker)
        #expect(drawn.customLook.background == look.background)
        #expect(drawn.customLook.text == look.text)
        #expect(drawn.customLook.accent == look.accent)
        #expect(drawn.speed == mine.speed)
        #expect(mine.drawn(with: nil) == mine)
        var auto = look
        auto.ticker = nil
        #expect(mine.drawn(with: auto).tickerColor == nil)
    }

    // hexReadsAndWrites reads #RRGGBB in either case and writes it back in capitals.
    @Test func hexReadsAndWrites() {
        #expect(StoredColor(hex: "#ff8000")?.hex == "#FF8000")
        #expect(StoredColor(hex: "ff8000") == nil)
        #expect(StoredColor(hex: "#ff800") == nil)
        #expect(StoredColor(red: 1, green: 0.5, blue: 0).hex == "#FF8000")
    }
}
