import Foundation
import Testing

@testable import CrierKit

// FeedParserTests covers RSS, Atom, dates, outlet suffixes, ranking, and bad input.
struct FeedParserTests {
    // rss reads items, strips Google's outlet suffix, takes the outlet from the source element, and ranks
    // stories in feed order.
    @Test func rss() throws {
        let xml = """
            <?xml version="1.0"?>
            <rss version="2.0"><channel><title>Top</title>
            <item><title>Senate passes   budget - Reuters</title><link>https://example.com/a</link>
            <pubDate>Wed, 18 Nov 2026 11:00:00 GMT</pubDate><source url="https://reuters.com">Reuters</source></item>
            <item><title><![CDATA[Probe reaches Mars]]></title><link>https://example.com/b</link>
            <pubDate>Wed, 18 Nov 2026 10:30:00 +0000</pubDate><source>NASA</source></item>
            <item><title>No link here</title><source>Nobody</source></item>
            </channel></rss>
            """
        let stories = try FeedParser.parse(Data(xml.utf8), source: googleSource)
        #expect(stories.map(\.title) == ["Senate passes budget", "Probe reaches Mars"])
        #expect(stories.map(\.outlet) == ["Reuters", "NASA"])
        #expect(stories.map(\.rank) == [0, 1])
        #expect(stories[0].published == noon.addingTimeInterval(-3600))
        #expect(stories[1].published == noon.addingTimeInterval(-5400))
    }

    // atom reads entries with link attributes and ISO dates, with and without fractional seconds.
    @Test func atom() throws {
        let xml = """
            <?xml version="1.0" encoding="utf-8"?>
            <feed xmlns="http://www.w3.org/2005/Atom"><title>Tech</title>
            <entry><title>Chip maker beats estimates</title>
            <link rel="alternate" href="https://example.com/c"/><link rel="replies" href="https://example.com/x"/>
            <published>2026-11-18T11:00:00Z</published></entry>
            <entry><title>Rocket lands</title><link href="https://example.com/d"/>
            <updated>2026-11-18T09:00:00.250Z</updated></entry>
            </feed>
            """
        let stories = try FeedParser.parse(Data(xml.utf8), source: feedSource)
        #expect(stories.map(\.link.absoluteString) == ["https://example.com/c", "https://example.com/d"])
        #expect(stories.map(\.outlet) == ["Test Outlet", "Test Outlet"])
        #expect(stories.map(\.rank) == [nil, nil])
        #expect(stories[0].published == noon.addingTimeInterval(-3600))
        #expect(stories[1].published == noon.addingTimeInterval(-3 * 3600 + 0.25))
    }

    // unreadableDates leave the date empty rather than dropping the story.
    @Test func unreadableDates() throws {
        let xml = """
            <rss><channel><item><title>Odd date</title><link>https://example.com/e</link>
            <pubDate>sometime</pubDate></item></channel></rss>
            """
        let stories = try FeedParser.parse(Data(xml.utf8), source: feedSource)
        #expect(stories.count == 1)
        #expect(stories[0].published == nil)
    }

    // malformed throws for a document XMLParser cannot read.
    @Test func malformed() {
        #expect(throws: FeedError.self) {
            try FeedParser.parse(Data("<rss><channel><item>".utf8), source: feedSource)
        }
    }

    // strip leaves a title alone when the suffix names another outlet or is the whole title.
    @Test func strip() {
        #expect(FeedParser.strip(outlet: "AP", from: "Storm hits coast - AP") == "Storm hits coast")
        #expect(FeedParser.strip(outlet: "AP", from: "Storm hits coast - BBC") == "Storm hits coast - BBC")
        #expect(FeedParser.strip(outlet: "AP", from: " - AP") == " - AP")
    }
}
