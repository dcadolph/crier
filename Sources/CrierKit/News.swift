import Foundation
import Observation

// Entry is one item in the ticker.
public struct Entry: Sendable, Hashable, Identifiable {
    // headline is the event shown.
    public let headline: Headline
    // tag names the follow the headline came from, or nil for general news.
    public let tag: String?
    // major reports whether the event passes the alert rules' outlet count.
    public let major: Bool

    // id is the headline's id.
    public var id: String {
        headline.id
    }

    // init builds an entry.
    public init(headline: Headline, tag: String?, major: Bool) {
        self.headline = headline
        self.tag = tag
        self.major = major
    }
}

// Fetch reads the body of a web address.
public typealias Fetch = @Sendable (URL) async throws -> Data

// News reads the feeds on a timer and keeps the ranked headlines and the ticker entries current.
@MainActor
@Observable
public final class News {
    // headlines are every event from the general feeds, most important first, pop culture and sports
    // already screened out unless major.
    public private(set) var headlines: [Headline] = []
    // entries are the ticker's items: the top general headlines with each follow's newest stories mixed in.
    public private(set) var entries: [Entry] = []
    // listed are the ticker's entries followed by every other headline, for a full list of the news.
    public var listed: [Entry] {
        let shown = Set(entries.map(\.id))
        let rules = settings.alerts
        return entries
            + headlines.filter { !shown.contains($0.id) }.map {
                Entry(headline: $0, tag: nil, major: Alerts.major($0, rules: rules))
            }
    }

    // updated is when the last refresh finished.
    public private(set) var updated: Date?
    // failures maps a feed id to the reason its last read failed.
    public private(set) var failures: [String: String] = [:]
    // refreshing reports whether a refresh is running.
    public private(set) var refreshing = false

    // settings are the reader's choices. Changing them takes effect on the next refresh.
    public var settings: Settings
    // onRefresh runs after every refresh with the new headlines. first is true for the first refresh after
    // launch, so callers can skip alerts for stories that were already out.
    @ObservationIgnored public var onRefresh: ((_ headlines: [Headline], _ first: Bool) -> Void)?

    // fetch reads one feed.
    @ObservationIgnored private let fetch: Fetch
    // cache keeps each feed's last good stories, so one failed read never empties the ticker.
    @ObservationIgnored private var cache: [String: [Story]] = [:]
    // loop is the timer task.
    @ObservationIgnored private var loop: Task<Void, Never>?
    // refreshed counts finished refreshes.
    @ObservationIgnored private var refreshed = 0

    // maxEntries is how many general headlines the ticker carries.
    public static let maxEntries = 24
    // perFollow is how many stories each follow adds to the ticker.
    public static let perFollow = 2
    // freshness is how old a story may be and stay in the ticker.
    public static let freshness: TimeInterval = 24 * 3600

    // init builds the model. fetch defaults to a plain HTTPS read.
    public init(settings: Settings = Settings(), fetch: @escaping Fetch = News.download) {
        self.settings = settings
        self.fetch = fetch
    }

    // start refreshes now and then on the settings' interval until stop.
    public func start() {
        loop?.cancel()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                let minutes = self?.settings.refreshMinutes ?? 5
                try? await Task.sleep(for: .seconds(max(1, minutes) * 60))
            }
        }
    }

    // stop ends the timer.
    public func stop() {
        loop?.cancel()
        loop = nil
    }

    // refresh reads every feed at once, then rebuilds the headlines and entries.
    public func refresh() async {
        guard !refreshing else {
            return
        }
        refreshing = true
        defer { refreshing = false }
        let sources = settings.sources
        let fetch = fetch
        let results = await withTaskGroup(of: (Source, Result<[Story], Error>).self) { group in
            for source in sources {
                group.addTask {
                    do {
                        return (source, .success(try FeedParser.parse(try await fetch(source.url), source: source)))
                    } catch {
                        return (source, .failure(error))
                    }
                }
            }
            var all: [(Source, Result<[Story], Error>)] = []
            for await result in group {
                all.append(result)
            }
            return all
        }
        var failed: [String: String] = [:]
        for (source, result) in results {
            switch result {
            case .success(let stories):
                cache[source.id] = stories
            case .failure(let error):
                failed[source.id] = String(describing: error)
            }
        }
        let ids = Set(sources.map(\.id))
        cache = cache.filter { ids.contains($0.key) }
        failures = failed
        rebuild(sources: sources, now: Date())
        updated = Date()
        refreshed += 1
        onRefresh?(headlines, refreshed == 1)
    }

    // rebuild ranks the cached stories into headlines and lays out the ticker entries.
    func rebuild(sources: [Source], now: Date) {
        let byID = Dictionary(sources.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let fresh: (Story) -> Bool = { story in
            guard let published = story.published else {
                return true
            }
            return now.timeIntervalSince(published) < Self.freshness
        }
        var general: [Story] = []
        var muted: [Story] = []
        var followed: [String: [Story]] = [:]
        for (id, stories) in cache {
            guard let source = byID[id] else {
                continue
            }
            let kept = stories.filter(fresh)
            switch source.topic {
            case .entertainment, .sports:
                muted += kept
            case .follow:
                followed[id] = kept
            default:
                general += kept
            }
        }
        let mutedWords = muted.map { Coverage.keywords($0.title) }
        let mutedLinks = Set(muted.map(\.id))
        let rules = settings.alerts
        headlines = Coverage.group(general).filter { headline in
            if Alerts.major(headline, rules: rules) {
                return true
            }
            let screened = headline.stories.contains { story in
                mutedLinks.contains(story.id)
                    || mutedWords.contains { Coverage.same($0, Coverage.keywords(story.title)) }
            }
            return !screened
        }
        var items = headlines.prefix(Self.maxEntries).map {
            Entry(headline: $0, tag: nil, major: Alerts.major($0, rules: rules))
        }
        var shown = Set(items.map(\.headline.keywords))
        var slot = 3
        for follow in settings.follows {
            guard let source = follow.source else {
                continue
            }
            let stories = (followed[source.id] ?? []).filter { follow.matches($0.title) }.sorted {
                ($0.published ?? .distantPast) > ($1.published ?? .distantPast)
            }
            var added = 0
            for headline in Coverage.group(stories) where added < Self.perFollow {
                if shown.contains(where: { Coverage.same($0, headline.keywords) }) {
                    continue
                }
                shown.insert(headline.keywords)
                items.insert(Entry(headline: headline, tag: follow.name, major: false), at: min(slot, items.count))
                slot += 4
                added += 1
            }
        }
        entries = items
    }

    // download reads a web address with a short timeout and a plain user agent, and refuses any status
    // other than 200.
    public nonisolated static func download(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("Crier/0.1 (macOS news ticker)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw FeedError.status(http.statusCode)
        }
        return data
    }
}
