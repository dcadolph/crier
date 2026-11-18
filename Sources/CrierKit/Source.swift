import Foundation

// Topic is a group of feeds the reader can weigh, from off to more.
public enum Topic: String, CaseIterable, Codable, Sendable, Comparable {
    case top
    case world
    case us
    case business
    case tech
    case science
    case movies
    case music
    case games
    case entertainment
    case sports
    case follow

    // title names the topic in settings.
    public var title: String {
        switch self {
        case .top: "Top stories"
        case .world: "World affairs"
        case .us: "U.S. and politics"
        case .business: "Economy and business"
        case .tech: "Tech and software"
        case .science: "Science and space"
        case .movies: "Movies and TV"
        case .music: "Music"
        case .games: "Video games"
        case .entertainment: "Pop culture and celebrity"
        case .sports: "Sports"
        case .follow: "Following"
        }
    }

    // choosable lists the topics the reader can weigh, in the order settings shows them.
    public static let choosable: [Topic] = allCases.filter { $0 != .follow }

    // < orders topics as settings lists them.
    public static func < (a: Topic, b: Topic) -> Bool {
        allCases.firstIndex(of: a)! < allCases.firstIndex(of: b)!
    }
}

// Interest is how much of a topic the reader wants. A headline takes the interest held by most of its stories,
// the lower one on a tie, not counting the general top story feeds. A game story that one tech feed picks up
// still counts as games, and a tech story that one game site picks up still counts as tech.
public enum Interest: String, CaseIterable, Codable, Sendable, Comparable {
    // off stops reading the topic's feeds.
    case off
    // majorOnly hides the topic's stories, and stories like them elsewhere, until they are major.
    case majorOnly
    // less shows the topic's stories lower down, and needs twice the outlets to call one major.
    case less
    // normal ranks the topic's stories by outlet count alone.
    case normal
    // more ranks the topic's stories higher.
    case more

    // title names the level in settings.
    public var title: String {
        switch self {
        case .off: "Off"
        case .majorOnly: "Major only"
        case .less: "Less"
        case .normal: "Normal"
        case .more: "More"
        }
    }

    // help explains the level in a tooltip.
    public var help: String {
        switch self {
        case .off: "Crier stops reading these feeds."
        case .majorOnly: "Hidden, along with stories like them from other feeds, until a story is major."
        case .less: "Shown lower down. A story needs twice the usual outlets to count as major."
        case .normal: "Ranked by how many outlets carry each story."
        case .more: "Ranked higher, as if half again as many outlets carried each story."
        }
    }

    // weight scales a headline's outlet count when ranking.
    public var weight: Double {
        switch self {
        case .off, .less: 0.5
        case .majorOnly, .normal: 1
        case .more: 1.5
        }
    }

    // majorFactor multiplies the outlets a headline needs to count as major.
    public var majorFactor: Int {
        self == .less ? 2 : 1
    }

    // < orders levels from off to more.
    public static func < (a: Interest, b: Interest) -> Bool {
        allCases.firstIndex(of: a)! < allCases.firstIndex(of: b)!
    }

    // defaults lean toward world affairs, politics, tech, and science, keep movies, music, and games in the mix
    // lower down, and hold pop culture and sports back until a story is major.
    public static let defaults: [Topic: Interest] = [
        .top: .normal, .world: .more, .us: .more, .business: .normal, .tech: .more, .science: .more,
        .movies: .less, .music: .less, .games: .less, .entertainment: .majorOnly, .sports: .majorOnly,
    ]
}

// Source is one free public news feed.
public struct Source: Sendable, Hashable, Identifiable {
    // id names the feed in logs and the failure list.
    public let id: String
    // outlet is the publisher behind every story in the feed, or nil when each item names its own, as
    // Google News items do.
    public let outlet: String?
    // url is the RSS or Atom address.
    public let url: URL
    // topic is the group the feed belongs to.
    public let topic: Topic
    // ranked reports whether the feed's order is an editor's ranking of importance.
    public let ranked: Bool

    // init builds a source.
    public init(id: String, outlet: String?, url: URL, topic: Topic, ranked: Bool = false) {
        self.id = id
        self.outlet = outlet
        self.url = url
        self.topic = topic
        self.ranked = ranked
    }

    // catalog lists every feed Crier reads. All are free and need no account or key.
    public static let catalog: [Source] = [
        google("google-top", path: "", topic: .top, ranked: true),
        outlet("npr", "NPR", "https://feeds.npr.org/1001/rss.xml", .top),
        outlet("nyt", "The New York Times", "https://rss.nytimes.com/services/xml/rss/nyt/HomePage.xml", .top),
        outlet("cbs", "CBS News", "https://www.cbsnews.com/latest/rss/main", .top),
        outlet("abc", "ABC News", "https://feeds.abcnews.com/abcnews/topstories", .top),
        outlet("pbs", "PBS News", "https://www.pbs.org/newshour/feeds/rss/headlines", .top),
        google("google-world", path: "/headlines/section/topic/WORLD", topic: .world),
        outlet("bbc-world", "BBC News", "https://feeds.bbci.co.uk/news/world/rss.xml", .world),
        outlet("guardian-world", "The Guardian", "https://www.theguardian.com/world/rss", .world),
        outlet("aljazeera", "Al Jazeera", "https://www.aljazeera.com/xml/rss/all.xml", .world),
        google("google-us", path: "/headlines/section/topic/NATION", topic: .us),
        outlet("guardian-us", "The Guardian", "https://www.theguardian.com/us-news/rss", .us),
        google("google-business", path: "/headlines/section/topic/BUSINESS", topic: .business),
        google("google-tech", path: "/headlines/section/topic/TECHNOLOGY", topic: .tech),
        outlet("ars", "Ars Technica", "https://feeds.arstechnica.com/arstechnica/index", .tech),
        outlet("verge", "The Verge", "https://www.theverge.com/rss/index.xml", .tech),
        outlet("hn", "Hacker News", "https://news.ycombinator.com/rss", .tech),
        google("google-science", path: "/headlines/section/topic/SCIENCE", topic: .science),
        outlet("space", "Space.com", "https://www.space.com/feeds.xml", .science),
        outlet("spacenews", "SpaceNews", "https://spacenews.com/feed/", .science),
        outlet("variety", "Variety", "https://variety.com/feed/", .movies),
        outlet("thr", "The Hollywood Reporter", "https://www.hollywoodreporter.com/feed/", .movies),
        outlet("deadline", "Deadline", "https://deadline.com/feed/", .movies),
        outlet("billboard", "Billboard", "https://www.billboard.com/feed/", .music),
        outlet("rollingstone", "Rolling Stone", "https://www.rollingstone.com/music/feed/", .music),
        outlet("pitchfork", "Pitchfork", "https://pitchfork.com/feed/feed-news/rss", .music),
        outlet("ign", "IGN", "https://feeds.feedburner.com/ign/news", .games),
        outlet("gamespot", "GameSpot", "https://www.gamespot.com/feeds/news/", .games),
        outlet("kotaku", "Kotaku", "https://kotaku.com/feed", .games),
        google("google-entertainment", path: "/headlines/section/topic/ENTERTAINMENT", topic: .entertainment),
        google("google-sports", path: "/headlines/section/topic/SPORTS", topic: .sports),
    ]

    // name labels the feed in settings: its outlet, or for a Google News feed, Google News and its section.
    public var name: String {
        if let outlet {
            return id.hasPrefix("guardian-") ? "\(outlet) \(topic == .world ? "World" : "U.S.")" : outlet
        }
        return topic == .top ? "Google News" : "Google News \(topic.title)"
    }

    // sources returns the catalog feeds for every topic not turned off, plus one search feed per follow.
    public static func sources(for interest: [Topic: Interest], follows: [Follow] = []) -> [Source] {
        catalog.filter { (interest[$0.topic] ?? .normal) != .off } + follows.compactMap(\.source)
    }

    // search builds a Google News search feed for a query, limited to the last two days.
    static func search(id: String, query: String) -> Source? {
        var parts = URLComponents(string: "https://news.google.com/rss/search")!
        parts.queryItems = [
            URLQueryItem(name: "q", value: "\(query) when:2d"), URLQueryItem(name: "hl", value: "en-US"),
            URLQueryItem(name: "gl", value: "US"), URLQueryItem(name: "ceid", value: "US:en"),
        ]
        guard let url = parts.url else {
            return nil
        }
        return Source(id: id, outlet: nil, url: url, topic: .follow)
    }

    // google builds a Google News feed for United States English.
    private static func google(_ id: String, path: String, topic: Topic, ranked: Bool = false) -> Source {
        let url = URL(string: "https://news.google.com/rss\(path)?hl=en-US&gl=US&ceid=US:en")!
        return Source(id: id, outlet: nil, url: url, topic: topic, ranked: ranked)
    }

    // outlet builds a feed published by a single outlet.
    private static func outlet(_ id: String, _ name: String, _ url: String, _ topic: Topic) -> Source {
        Source(id: id, outlet: name, url: URL(string: url)!, topic: topic)
    }
}

// Follow is a team, person, or subject the reader wants kept in the ticker, found by a news search.
public struct Follow: Codable, Sendable, Hashable, Identifiable {
    // name is the short label shown before the follow's headlines.
    public var name: String
    // query is the Google News search, in quotes for an exact phrase.
    public var query: String

    // init builds a follow.
    public init(name: String, query: String) {
        self.name = name
        self.query = query
    }

    // id is the follow's label.
    public var id: String {
        name
    }

    // source is the follow's search feed, or nil when the query is blank.
    public var source: Source? {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            return nil
        }
        return Source.search(id: "follow:\(name)", query: trimmed)
    }

    // junk are title phrases that mark betting tips, schedules, and hub pages rather than news.
    static let junk = [
        "odds", "picks", "prediction", "best bet", "betting", "props", "news & analysis", "how to watch",
        "live stream", "live score", "tickets", "fantasy",
    ]

    // matches reports whether a story belongs in the ticker for this follow: its title must name the follow,
    // and must not read like betting tips, a schedule, or a hub page.
    public func matches(_ title: String) -> Bool {
        let lower = title.lowercased()
        let label = name.lowercased().trimmingCharacters(in: .whitespaces)
        guard label.isEmpty || lower.contains(label) else {
            return false
        }
        return !Self.junk.contains { lower.contains($0) }
    }

    // defaults are the follows a new install starts with.
    public static let defaults: [Follow] = [
        Follow(name: "49ers", query: "\"San Francisco 49ers\""),
        Follow(name: "Giants", query: "\"San Francisco Giants\""),
        Follow(name: "Austin FC", query: "\"Austin FC\""),
    ]
}
