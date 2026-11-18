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
        settings.interest = Dictionary(uniqueKeysWithValues: Topic.choosable.map { ($0, Interest.off) })
        settings.interest[.top] = .normal
        settings.interest[.entertainment] = .majorOnly
        settings.interest[.sports] = .majorOnly
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

    // interestRanks weighs outlet counts by topic: a tech story wanted more beats a wider game story wanted
    // less, a game story carried by a top feed still counts as games, and a tech story one game site picks up
    // still counts as tech.
    @Test func interestRanks() async {
        var settings = Settings()
        settings.interest = Dictionary(uniqueKeysWithValues: Topic.choosable.map { ($0, Interest.off) })
        settings.interest[.top] = .normal
        settings.interest[.tech] = .more
        settings.interest[.games] = .less
        let kept: Set<String> = ["google-top", "npr", "ars", "verge", "ign", "gamespot"]
        settings.disabledSources = Set(Source.catalog.map(\.id).filter { !kept.contains($0) })
        settings.follows = []
        let fetch: Fetch = { url in
            let text = url.absoluteString
            if text.contains("npr") {
                return Self.rss(["Senate passes sweeping budget bill"], outlet: "NPR")
            }
            if text.contains("arstechnica") {
                return Self.rss(["Chip maker unveils faster laptop processor"], outlet: "Ars")
            }
            if text.contains("theverge") {
                return Self.rss(["Chip maker unveils faster laptop processor"], outlet: "Verge")
            }
            if text.contains("ign") {
                return Self.rss(
                    ["Console maker reveals new handheld", "Chip maker unveils faster laptop processor"], outlet: "IGN")
            }
            if text.contains("gamespot") {
                return Self.rss(["Console maker reveals new handheld"], outlet: "GameSpot")
            }
            return Self.rss(
                [
                    "Senate passes sweeping budget bill", "Console maker reveals new handheld",
                    "Chip maker unveils faster laptop processor",
                ], outlet: "Wire")
        }
        let news = News(settings: settings, fetch: fetch)
        await news.refresh()
        #expect(news.failures.isEmpty)
        #expect(
            news.headlines.map(\.lead.title) == [
                "Chip maker unveils faster laptop processor", "Senate passes sweeping budget bill",
                "Console maker reveals new handheld",
            ])
        #expect(news.headlines.map(\.interest) == [.more, .normal, .less])
        #expect(news.headlines.map(\.outlets.count) == [4, 2, 3])
    }
}
