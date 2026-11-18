import Foundation

// Headline is one news event: every story from every feed that reports it.
public struct Headline: Sendable, Hashable, Identifiable {
    // lead is the story whose title and link represent the event: the best ranked or newest story whose title
    // covers this event alone, falling back to the first story when every title is a roundup.
    public let lead: Story
    // stories holds every story about the event, lead first.
    public let stories: [Story]
    // outlets lists the distinct publishers reporting the event, sorted by name.
    public let outlets: [String]
    // keywords are the lead title's significant words, used to recognize the event again later.
    public let keywords: Set<String>

    // id is the lead story's id.
    public var id: String {
        lead.id
    }

    // first is the earliest publish date among the stories, if any has one.
    public var first: Date? {
        stories.compactMap(\.published).min()
    }

    // latest is the newest publish date among the stories, if any has one. It says how fresh the event is.
    public var latest: Date? {
        stories.compactMap(\.published).max()
    }

    // rank is the best editor ranking among the stories, if any feed ranks one.
    public var rank: Int? {
        stories.compactMap(\.rank).min()
    }
}

// Coverage groups stories about the same event and ranks the events.
public enum Coverage {
    // stopWords are common words that say nothing about which event a headline covers.
    static let stopWords: Set<String> = [
        "the", "and", "for", "with", "from", "into", "over", "after", "about", "than", "this", "that", "what",
        "who", "how", "why", "will", "can", "could", "may", "not", "but", "his", "her", "their", "they", "she",
        "you", "our", "out", "off", "down", "are", "was", "were", "been", "has", "have", "had", "its", "more",
        "new", "amid", "says", "said", "live", "update", "updates", "latest", "news", "video", "watch",
    ]

    // keywords returns a title's significant words: lowercased, three letters or longer, without stop words,
    // and with a plural "s" dropped from longer words so "flips" matches "flip".
    public static func keywords(_ title: String) -> Set<String> {
        let folded = title.lowercased().replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "\u{2019}", with: "")
        var words = Set<String>()
        for part in folded.split(whereSeparator: { !$0.isLetter && !$0.isNumber }) {
            var word = String(part)
            guard word.count >= 3, !stopWords.contains(word) else {
                continue
            }
            if word.count > 4, word.hasSuffix("s") {
                word.removeLast()
            }
            words.insert(word)
        }
        return words
    }

    // same reports whether two keyword sets describe one event: at least three shared words, covering at
    // least half of the shorter set.
    public static func same(_ a: Set<String>, _ b: Set<String>) -> Bool {
        let shared = a.intersection(b).count
        let shorter = min(a.count, b.count)
        return shared >= 3 && shorter > 0 && Double(shared) / Double(shorter) >= 0.5
    }

    // roundupMarkers are phrases that mark a newsletter or digest title rather than a single story.
    static let roundupMarkers = [
        "morning brief", "morning bid", "evening brief", "daily brief", "newsletter", "roundup", "round-up",
        "what to know today", "the week in", "the day in", "headlines today", "top stories",
    ]

    // abbreviations end with a period inside a single-story title, so a period after one is no sentence break.
    static let abbreviations: Set<String> = [
        "mr", "mrs", "ms", "dr", "st", "jr", "sr", "gov", "sen", "rep", "gen", "lt", "col", "sgt", "inc", "corp",
        "ltd", "co", "vs", "no", "jan", "feb", "mar", "apr", "aug", "sept", "sep", "oct", "nov", "dec", "est",
    ]

    // roundup reports whether a title reads as a digest of several stories: it carries a newsletter marker, or
    // a period ends a sentence and another begins inside it, as in "Peltola flips Alaska's seat. And, Nvidia
    // won't reinstate Huang". Question and exclamation marks do not count, since single-story titles use them.
    public static func roundup(_ title: String) -> Bool {
        let folded = title.lowercased()
        if roundupMarkers.contains(where: { folded.contains($0) }) {
            return true
        }
        let words = title.split(separator: " ")
        for (index, word) in words.enumerated() where index < words.count - 1 && word.hasSuffix(".") {
            let stem = word.dropLast().trimmingCharacters(in: .punctuationCharacters)
            guard stem.count >= 2, !stem.contains("."), !abbreviations.contains(stem.lowercased()) else {
                continue
            }
            if stem.count <= 2, stem == stem.uppercased() {
                continue
            }
            if let next = words[index + 1].first(where: \.isLetter), next.isUppercase {
                return true
            }
        }
        return false
    }

    // outletKey folds an outlet name so "The Guardian" and "Guardian" count once.
    static func outletKey(_ outlet: String) -> String {
        var key = outlet.lowercased().trimmingCharacters(in: .whitespaces)
        if key.hasPrefix("the ") {
            key.removeFirst(4)
        }
        return key
    }

    // group gathers stories into headlines and returns them most important first: more outlets first, then
    // a better editor ranking, then the newest.
    public static func group(_ stories: [Story]) -> [Headline] {
        let ordered = stories.sorted { a, b in
            switch (a.rank, b.rank) {
            case let (x?, y?): return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return (a.published ?? .distantPast) > (b.published ?? .distantPast)
            }
        }
        var groups: [(keywords: [Set<String>], stories: [Story])] = []
        var seenLinks = Set<String>()
        for story in ordered where seenLinks.insert(story.id).inserted {
            let words = keywords(story.title)
            if let index = groups.firstIndex(where: { group in group.keywords.contains { same($0, words) } }) {
                groups[index].keywords.append(words)
                groups[index].stories.append(story)
            } else {
                groups.append((keywords: [words], stories: [story]))
            }
        }
        let headlines = groups.map { group in
            var names: [String: String] = [:]
            for story in group.stories {
                names[outletKey(story.outlet)] = names[outletKey(story.outlet)] ?? story.outlet
            }
            let lead = group.stories.firstIndex { !roundup($0.title) } ?? 0
            var stories = group.stories
            stories.insert(stories.remove(at: lead), at: 0)
            return Headline(
                lead: stories[0], stories: stories, outlets: names.values.sorted(), keywords: group.keywords[lead]
            )
        }
        return headlines.sorted { a, b in
            if a.outlets.count != b.outlets.count {
                return a.outlets.count > b.outlets.count
            }
            switch (a.rank, b.rank) {
            case let (x?, y?) where x != y: return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return (a.first ?? .distantPast) > (b.first ?? .distantPast)
            }
        }
    }
}
