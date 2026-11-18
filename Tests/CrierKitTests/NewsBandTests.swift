import CoreGraphics
import Testing

@testable import CrierKit

// NewsBandTests covers how many stories the band pins and how it splits them into pages and the ticker.
@MainActor
struct NewsBandTests {
    // columns fits stories to the width, from three to five.
    @Test func columns() {
        #expect(NewsBand.columns(for: 0) == 3)
        #expect(NewsBand.columns(for: 1000) == 3)
        #expect(NewsBand.columns(for: 1400) == 3)
        #expect(NewsBand.columns(for: 1456) == 4)
        #expect(NewsBand.columns(for: 1796) == 5)
        #expect(NewsBand.columns(for: 5120) == 5)
    }

    // general builds count untagged entries.
    private func general(_ count: Int) -> [Entry] {
        (0..<count).map { entry("General story number \($0) about events") }
    }

    // pagesAreWhole pins about twelve stories in whole pages and leaves the rest to the ticker.
    @Test func pagesAreWhole() {
        let entries = general(24)
        for (columns, pages) in [(3, 4), (4, 3), (5, 2)] {
            let layout = NewsBand.layout(entries, columns: columns)
            #expect(layout.pages.count == pages)
            #expect(layout.pages.allSatisfy { $0.count == columns })
            #expect(layout.rest.count == 24 - pages * columns)
            #expect(layout.pages.flatMap { $0 } + layout.rest == entries)
        }
    }

    // shortNewsMakesPartialPage pins every story when there are fewer than one page's worth, and drops a
    // partial last page into the ticker otherwise.
    @Test func shortNews() {
        let two = NewsBand.layout(general(2), columns: 3)
        #expect(two.pages.map(\.count) == [2])
        #expect(two.rest.isEmpty)
        let seven = NewsBand.layout(general(7), columns: 3)
        #expect(seven.pages.map(\.count) == [3, 3])
        #expect(seven.rest.count == 1)
        #expect(NewsBand.layout([], columns: 3).pages.isEmpty)
    }

    // followsGoToTicker never pins a followed story and spreads them one after every three general stories.
    @Test func followsGoToTicker() {
        let follows = (0..<3).map { entry("Team story number \($0) about the match", tag: "49ers") }
        let layout = NewsBand.layout(follows + general(20), columns: 4)
        #expect(layout.pages.flatMap { $0 }.allSatisfy { $0.tag == nil })
        let tags = layout.rest.map { $0.tag != nil }
        #expect(tags.enumerated().filter(\.element).map(\.offset) == [1, 5, 9])
    }
}
