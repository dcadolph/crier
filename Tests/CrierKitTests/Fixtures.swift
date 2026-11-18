import Foundation

@testable import CrierKit

// noon is Wednesday, November 18, 2026 at 12:00:00 UTC.
let noon = Date(timeIntervalSince1970: 1_795_003_200)

// utcCalendar reads hours in UTC so quiet hour cases hold on every machine.
let utcCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

// story builds a story with a link made from its title.
func story(
    _ title: String, outlet: String = "Outlet", hoursAgo: Double? = 1, source: String = "feed", rank: Int? = nil
) -> Story {
    let slug = title.lowercased().filter { $0.isLetter || $0.isNumber }
    return Story(
        title: title, link: URL(string: "https://example.com/\(outlet.filter(\.isLetter))/\(slug)")!, outlet: outlet,
        published: hoursAgo.map { noon.addingTimeInterval(-$0 * 3600) }, sourceID: source, rank: rank)
}

// headline builds a headline carried by the given number of outlets.
func headline(_ title: String, outlets: Int, hoursAgo: Double = 1) -> Headline {
    let stories = (0..<max(outlets, 1)).map { story(title, outlet: "Outlet \($0)", hoursAgo: hoursAgo) }
    return Headline(
        lead: stories[0], stories: stories, outlets: stories.map(\.outlet).sorted(),
        keywords: Coverage.keywords(title))
}

// entry builds a ticker entry for a headline, tagged when it came from a follow.
func entry(_ title: String, tag: String? = nil, outlets: Int = 1) -> Entry {
    Entry(headline: headline(title, outlets: outlets), tag: tag, major: outlets >= 6)
}

// feedSource is a plain outlet feed for parser cases.
let feedSource = Source(id: "test", outlet: "Test Outlet", url: URL(string: "https://example.com/feed")!, topic: .top)

// googleSource is a ranked feed whose items name their own outlet, as Google News does.
let googleSource = Source(
    id: "google", outlet: nil, url: URL(string: "https://example.com/google")!, topic: .top, ranked: true)
