import Foundation

// FeedError describes why a feed could not be read.
public enum FeedError: Error, Equatable {
    // malformed means the document is not RSS or Atom that XMLParser can read.
    case malformed(String)
    // status means the server answered with a code other than 200.
    case status(Int)
}

// FeedParser turns an RSS 2.0 or Atom document into stories.
public enum FeedParser {
    // parse reads every item or entry that has a title and a link. Ranked sources number their stories in
    // feed order.
    public static func parse(_ data: Data, source: Source) throws -> [Story] {
        let delegate = FeedDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else {
            throw FeedError.malformed(parser.parserError?.localizedDescription ?? "unknown parse error")
        }
        let dates = DateReader()
        var stories: [Story] = []
        for entry in delegate.entries {
            let rawTitle = clean(entry.title)
            let outlet = source.outlet ?? clean(entry.source)
            guard !rawTitle.isEmpty, !outlet.isEmpty,
                let link = URL(string: clean(entry.link)), link.scheme?.hasPrefix("http") == true
            else {
                continue
            }
            stories.append(
                Story(
                    title: strip(outlet: outlet, from: rawTitle), link: link, outlet: outlet,
                    published: dates.date(clean(entry.date)), sourceID: source.id,
                    rank: source.ranked ? stories.count : nil
                )
            )
        }
        return stories
    }

    // clean collapses runs of whitespace and trims the ends.
    static func clean(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    // strip removes a trailing " - Outlet" that Google News appends to every title.
    static func strip(outlet: String, from title: String) -> String {
        let suffix = " - \(outlet)"
        guard title.hasSuffix(suffix), title.count > suffix.count else {
            return title
        }
        return String(title.dropLast(suffix.count))
    }
}

// RawEntry is one item or entry as it is read.
private struct RawEntry {
    // title is the raw headline.
    var title = ""
    // link is the story address.
    var link = ""
    // date is the raw publish or update date.
    var date = ""
    // source is the publisher named inside the item, used by Google News.
    var source = ""
}

// FeedDelegate collects entries while XMLParser walks the document.
private final class FeedDelegate: NSObject, XMLParserDelegate {
    // entries holds every finished entry.
    var entries: [RawEntry] = []
    // current is the entry being read, or nil outside an item or entry.
    private var current: RawEntry?
    // text gathers the characters of the element being read.
    private var text = ""

    // parser starts an entry, or records an Atom link from its attributes.
    func parser(
        _ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
        attributes: [String: String] = [:]
    ) {
        text = ""
        switch name {
        case "item", "entry":
            current = RawEntry()
        case "link":
            let rel = attributes["rel"] ?? "alternate"
            if let href = attributes["href"], rel == "alternate", current?.link.isEmpty == true {
                current?.link = href
            }
        default:
            break
        }
    }

    // parser gathers element text.
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    // parser gathers CDATA text, which some feeds use for titles.
    func parser(_ parser: XMLParser, foundCDATA block: Data) {
        text += String(decoding: block, as: UTF8.self)
    }

    // parser files the element's text into the current entry, and closes the entry at its end.
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        guard current != nil else {
            return
        }
        switch name {
        case "title":
            current?.title = text
        case "link" where !text.isEmpty:
            current?.link = text
        case "pubDate", "published", "dc:date":
            current?.date = text
        case "updated" where current?.date.isEmpty == true:
            current?.date = text
        case "source":
            current?.source = text
        case "item", "entry":
            if let entry = current {
                entries.append(entry)
            }
            current = nil
        default:
            break
        }
        text = ""
    }
}

// DateReader parses the date formats news feeds use.
struct DateReader {
    // rfc822 reads RSS dates such as "Wed, 18 Nov 2026 03:19:00 GMT".
    private let rfc822: [DateFormatter]
    // iso reads Atom dates with and without fractional seconds.
    private let iso: [ISO8601DateFormatter]

    // init builds the formatters once per parse.
    init() {
        rfc822 = ["EEE, dd MMM yyyy HH:mm:ss zzz", "EEE, dd MMM yyyy HH:mm:ss Z", "dd MMM yyyy HH:mm:ss zzz"].map {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = $0
            return formatter
        }
        let plain = ISO8601DateFormatter()
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        iso = [plain, fractional]
    }

    // date returns the parsed date, or nil when no format matches.
    func date(_ text: String) -> Date? {
        guard !text.isEmpty else {
            return nil
        }
        for formatter in rfc822 {
            if let date = formatter.date(from: text) {
                return date
            }
        }
        for formatter in iso {
            if let date = formatter.date(from: text) {
                return date
            }
        }
        return nil
    }
}
