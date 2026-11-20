import Foundation

// Measure records how far the biggest headlines spread within an hour of their first report, and sums the
// records up, so the national tier's outlet counts can be picked from live feeds. Only the dev build's
// measuring log calls it.
public enum Measure {
    // Record is one headline as one refresh saw it.
    public struct Record: Codable, Sendable, Equatable {
        // at is when the refresh ran.
        public var at: Date
        // id is the lead story's id.
        public var id: String
        // title is the lead story's title.
        public var title: String
        // outlet is the lead story's outlet.
        public var outlet: String
        // first is the earliest publish date among the headline's stories.
        public var first: Date?
        // hour is how many outlets carried the headline within an hour of its first report.
        public var hour: Int
        // outlets is how many outlets carried the headline at any time.
        public var outlets: Int
        // phrase is the top tier phrase found in the headline's titles, if any, without its padding spaces.
        public var phrase: String?
        // tier is the national tier the rules in force give the headline.
        public var tier: String
        // keywords are the lead title's significant words, sorted, used to join a story whose lead changes.
        public var keywords: [String]
        // feeds is how many feeds the settings read at the time.
        public var feeds: Int
        // stories are the ids of every story in the headline, used to join a story whose lead and wording change.
        // Records written before it existed lack it.
        public var stories: [String]? = nil
    }

    // Peak is one story across every refresh that saw it.
    public struct Peak: Sendable, Equatable {
        // title is the lead title from the refresh with the highest hour count.
        public var title: String
        // outlet is the lead outlet from that refresh.
        public var outlet: String
        // first is the earliest first report seen for the story.
        public var first: Date?
        // hour is the highest count of outlets within an hour.
        public var hour: Int
        // outlets is the highest count of outlets at any time.
        public var outlets: Int
        // phrase is a top tier phrase any refresh found, if any.
        public var phrase: String?
        // ids are every lead and story id the story had.
        var ids: Set<String>
        // keywords are every keyword set the story's lead titles had.
        var keywords: Set<Set<String>>
    }

    // limit is how many headlines each refresh records.
    public static let limit = 10
    // thresholds are the outlet counts the summary tests.
    public static let thresholds = [8, 10, 12, 15, 20]
    // shown is how many stories the summary lists.
    public static let shown = 25
    // joinWindow is how far apart two first reports can be for matching keywords to join them, so a later event
    // worded like an earlier one starts its own story.
    public static let joinWindow: TimeInterval = 12 * 3600

    // records returns the headlines with the most outlets within an hour, up to the limit, as records. Ties
    // keep the order the headlines came in.
    public static func records(
        _ headlines: [Headline], rules: NationalRules, feeds: Int, at: Date, limit: Int = limit
    ) -> [Record] {
        let counted = headlines.map { ($0, Emergency.outletsWithin($0, window: 3600)) }
        let biggest = counted.enumerated().sorted { a, b in
            a.element.1 != b.element.1 ? a.element.1 > b.element.1 : a.offset < b.offset
        }.prefix(limit)
        return biggest.map { item in
            let (headline, hour) = item.element
            return Record(
                at: at, id: headline.id, title: headline.lead.title, outlet: headline.lead.outlet,
                first: headline.first, hour: hour, outlets: headline.outlets.count,
                phrase: Emergency.topPhrase(headline, rules: rules)?.trimmingCharacters(in: .whitespaces),
                tier: "\(Emergency.tier(headline, rules: rules))", keywords: headline.keywords.sorted(), feeds: feeds,
                stories: headline.stories.map(\.id))
        }
    }

    // encoder writes one record per line with ISO 8601 dates and sorted keys.
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    // lines encodes records as JSON lines, each ending in a newline.
    public static func lines(_ records: [Record]) throws -> Data {
        let encoder = encoder()
        var data = Data()
        for record in records {
            data.append(try encoder.encode(record))
            data.append(0x0A)
        }
        return data
    }

    // decode reads JSON lines back into records, skipping blank and broken lines so a torn write loses one line.
    public static func decode(_ data: Data) -> [Record] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return data.split(separator: 0x0A).compactMap { try? decoder.decode(Record.self, from: Data($0)) }
    }

    // fileName names the day's log file, e.g. "2026-11-19.jsonl", by the calendar's date.
    public static func fileName(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d.jsonl", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    // peaks joins records into stories, highest hour count first. A record joins every story that shares a lead
    // or story id with it, or that had keywords describing the same event, as Coverage.same decides, with a first
    // report within the join window. When one record joins several stories, they merge into one.
    public static func peaks(_ records: [Record]) -> [Peak] {
        var peaks: [Peak] = []
        for record in records.sorted(by: { $0.at < $1.at }) {
            var peak = Peak(
                title: record.title, outlet: record.outlet, first: record.first, hour: record.hour,
                outlets: record.outlets, phrase: record.phrase, ids: Set([record.id] + (record.stories ?? [])),
                keywords: [Set(record.keywords)])
            let matches = peaks.indices.filter { joins(peaks[$0], peak) }
            for index in matches {
                peak = merged(peaks[index], peak)
            }
            guard let first = matches.first else {
                peaks.append(peak)
                continue
            }
            peaks[first] = peak
            for index in matches.dropFirst().reversed() {
                peaks.remove(at: index)
            }
        }
        return peaks.enumerated().sorted { a, b in
            a.element.hour != b.element.hour ? a.element.hour > b.element.hour : a.offset < b.offset
        }.map(\.element)
    }

    // joins reports whether two stories are one: they share an id, or their keywords match and their first reports
    // fall within the join window. A story without a first report matches by keywords alone.
    static func joins(_ a: Peak, _ b: Peak) -> Bool {
        if !a.ids.isDisjoint(with: b.ids) {
            return true
        }
        if let x = a.first, let y = b.first, abs(x.timeIntervalSince(y)) > joinWindow {
            return false
        }
        return a.keywords.contains { words in b.keywords.contains { Coverage.same(words, $0) } }
    }

    // merged combines two stories, keeping the title and outlet from the higher hour count and, on a tie, from
    // the later story b.
    static func merged(_ a: Peak, _ b: Peak) -> Peak {
        var peak = b.hour >= a.hour ? b : a
        peak.hour = max(a.hour, b.hour)
        peak.outlets = max(a.outlets, b.outlets)
        peak.first = [a.first, b.first].compactMap { $0 }.min()
        peak.phrase = a.phrase ?? b.phrase
        peak.ids = a.ids.union(b.ids)
        peak.keywords = a.keywords.union(b.keywords)
        return peak
    }

    // summary writes the plain text report: the period, how many stories reach each threshold, and the biggest
    // stories with their peak counts.
    public static func summary(_ records: [Record], timeZone: TimeZone = .current) -> String {
        guard let start = records.map(\.at).min(), let end = records.map(\.at).max() else {
            return "No refreshes recorded yet.\n"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        let peaks = peaks(records)
        let refreshes = Set(records.map(\.at)).count
        let feeds = records.map(\.feeds)
        let feedText =
            feeds.min() == feeds.max() ? "\(feeds[0]) feeds" : "\(feeds.min() ?? 0) to \(feeds.max() ?? 0) feeds"
        var text = "Crier measuring log\n\n"
        text += "Period: \(formatter.string(from: start)) to \(formatter.string(from: end)), "
        text += "\(refreshes) refreshes, \(feedText), \(peaks.count) stories.\n\n"
        text += "Stories reaching each count of outlets within an hour of first report:\n\n"
        for threshold in thresholds {
            let reached = peaks.filter { $0.hour >= threshold }
            let phrased = reached.filter { $0.phrase != nil }.count
            let count = String(threshold).leftPadded(to: 3)
            text += "  \(count) outlets: \(reached.count) stories, \(phrased) with a top tier phrase\n"
        }
        text += "\nBiggest \(min(shown, peaks.count)) stories:\n\n"
        text += "  Hour  Total  First report      Title\n"
        for peak in peaks.prefix(shown) {
            let first = peak.first.map { formatter.string(from: $0) } ?? "Unknown".padding(16)
            let phrase = peak.phrase.map { " [\($0)]" } ?? ""
            let hour = String(peak.hour).leftPadded(to: 4)
            let total = String(peak.outlets).leftPadded(to: 5)
            text += "  \(hour)  \(total)  \(first)  \(peak.title) (\(peak.outlet))\(phrase)\n"
        }
        return text
    }
}

extension String {
    // leftPadded pads the string with spaces on the left to the width.
    fileprivate func leftPadded(to width: Int) -> String {
        String(repeating: " ", count: max(0, width - count)) + self
    }

    // padding pads the string with spaces on the right to the width.
    fileprivate func padding(_ width: Int) -> String {
        self + String(repeating: " ", count: max(0, width - count))
    }
}
