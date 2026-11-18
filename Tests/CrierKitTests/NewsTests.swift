import Foundation
import Testing

@testable import CrierKit

// NewsTests runs a refresh against canned feeds, with no network.
@MainActor
struct NewsTests {
    // rss builds a feed document from titles, each published an hour before now.
    private nonisolated static func rss(_ titles: [String], outlet: String) -> Data {
        let date = Date().addingTimeInterval(-3600).formatted(.iso8601)
        let items = titles.enumerated().map { index, title in
            "<item><title>\(title)</title><link>https://example.com/\(outlet)/\(index)</link>"
                + "<pubDate>\(date)</pubDate><source>\(outlet)</source></item>"
        }
        return Data("<rss><channel>\(items.joined())</channel></rss>".utf8)
    }

    // refresh screens pop culture, mixes in follows that name the team, records failures, and lists every
    // headline.
    @Test func refresh() async {
        var settings = Settings()
        settings.topics = [.top]
        settings.disabledSources = Set(Source.catalog.filter { $0.topic == .top && $0.id != "google-top" }.map(\.id))
        settings.follows = [Follow(name: "49ers", query: "\"San Francisco 49ers\"")]
        let fetch: Fetch = { url in
            let text = url.absoluteString
            if text.contains("ENTERTAINMENT") {
                return Self.rss(["Pop star announces stadium world tour dates"], outlet: "Gossip")
            }
            if text.contains("SPORTS") {
                throw FeedError.status(503)
            }
            if text.contains("search") {
                return Self.rss(
                    ["49ers beat Seahawks in overtime thriller", "Seahawks sign new kicker"], outlet: "Fan")
            }
            return Self.rss(
                [
                    "Senate passes sweeping budget bill", "Pop star announces stadium world tour",
                    "Rocket carries crew toward lunar orbit", "Chip maker beats quarterly estimates",
                    "Storm floods coastal towns overnight",
                ], outlet: "Wire")
        }
        let news = News(settings: settings, fetch: fetch)
        var first: Bool?
        news.onRefresh = { _, isFirst in first = isFirst }
        await news.refresh()
        let titles = news.headlines.map(\.lead.title)
        #expect(titles.count == 4)
        #expect(!titles.contains("Pop star announces stadium world tour"))
        #expect(news.entries.count == 5)
        #expect(news.entries[3].tag == "49ers")
        #expect(news.entries[3].headline.lead.title == "49ers beat Seahawks in overtime thriller")
        #expect(news.failures.keys.sorted() == ["google-sports"])
        #expect(news.failures["google-sports"] == "The server answered with status 503 instead of the feed.")
        #expect(news.listed.count == 5)
        #expect(first == true)
        await news.refresh()
        #expect(first == false)
    }
}
