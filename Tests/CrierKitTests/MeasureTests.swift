import Foundation
import Testing

@testable import CrierKit

// MeasureTests covers the measuring log's records, its file format, joining a story across refreshes, and the
// summary.
struct MeasureTests {
    // record builds a record seen at the given minutes after noon.
    private func record(
        _ title: String, id: String? = nil, minutes: Double = 0, hour: Int, outlets: Int? = nil,
        phrase: String? = nil
    ) -> Measure.Record {
        Measure.Record(
            at: noon.addingTimeInterval(minutes * 60), id: id ?? title, title: title, outlet: "Outlet",
            first: noon.addingTimeInterval(-3600), hour: hour, outlets: outlets ?? hour, phrase: phrase, tier: "none",
            keywords: Coverage.keywords(title).sorted(), feeds: 40)
    }

    // recordsKeepBiggest keeps the headlines with the most outlets within an hour, biggest first, up to the limit.
    @Test func recordsKeepBiggest() {
        let headlines = [
            headline("Mayor opens new library branch", outlets: 3),
            headline("Congress declares war after attack", outlets: 14),
            headline("Senate passes sweeping budget bill", outlets: 12),
            headline("Storm closes coastal highways", outlets: 3),
        ]
        let records = Measure.records(headlines, rules: NationalRules(), feeds: 40, at: noon, limit: 3)
        #expect(records.map(\.title) == [headlines[1], headlines[2], headlines[0]].map(\.lead.title))
        #expect(records.map(\.hour) == [14, 12, 3])
        #expect(records.map(\.tier) == ["top", "red", "none"])
        #expect(records[0].phrase == "declares war")
        #expect(records[1].phrase == nil)
        #expect(records[0].outlets == 14)
        #expect(records[0].feeds == 40)
        #expect(records[0].at == noon)
        #expect(records[0].first == noon.addingTimeInterval(-3600))
        #expect(records[0].keywords == ["attack", "congres", "declare", "war"])
    }

    // recordsCountOnlyTheHour counts outlets within an hour of first report and every outlet in total.
    @Test func recordsCountOnlyTheHour() {
        let early = (0..<4).map { story("Bridge collapses in the city", outlet: "Early \($0)", hoursAgo: 3) }
        let late = (0..<3).map { story("Bridge collapses in the city", outlet: "Late \($0)", hoursAgo: 1) }
        let all = early + late
        let event = Headline(lead: all[0], stories: all, outlets: all.map(\.outlet).sorted(), keywords: [])
        let records = Measure.records([event], rules: NationalRules(), feeds: 1, at: noon)
        #expect(records.map(\.hour) == [4])
        #expect(records.map(\.outlets) == [7])
    }

    // linesRoundTrip writes one line per record and reads them back, skipping blank and torn lines.
    @Test func linesRoundTrip() throws {
        let records = [record("Senate passes budget bill", hour: 9, phrase: "martial law"), record("Quiet", hour: 1)]
        let data = try Measure.lines(records)
        #expect(data.split(separator: 0x0A).count == 2)
        #expect(data.last == 0x0A)
        #expect(String(decoding: data, as: UTF8.self).contains("\"at\":\"2026-11-18T12:00:00Z\""))
        #expect(Measure.decode(data) == records)
        let torn = data + Data("\n{\"at\":\"2026-11-18T12:05".utf8)
        #expect(Measure.decode(torn) == records)
        #expect(Measure.decode(Data()).isEmpty)
    }

    // fileNameUsesTheDay names the file by the calendar's date.
    @Test func fileNameUsesTheDay() {
        #expect(Measure.fileName(for: noon, calendar: utcCalendar) == "2026-11-18.jsonl")
        var tokyo = utcCalendar
        tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        #expect(Measure.fileName(for: noon.addingTimeInterval(13 * 3600), calendar: tokyo) == "2026-11-19.jsonl")
    }

    // peaksJoinStories joins records by lead id or by matching keywords, keeps each story's highest counts, and
    // sorts the biggest first.
    @Test func peaksJoinStories() {
        let records = [
            record("Senate passes sweeping budget bill", id: "a", minutes: 0, hour: 6, outlets: 7),
            record("Senate passes sweeping budget bill", id: "a", minutes: 5, hour: 11, outlets: 12),
            record("Senate budget bill passes sweeping vote", id: "b", minutes: 10, hour: 9, outlets: 15),
            record("Bridge collapses in the city", id: "c", minutes: 5, hour: 8, phrase: "national emergency"),
            record("Bridge collapses in the city", id: "c", minutes: 10, hour: 4),
        ]
        let peaks = Measure.peaks(records)
        #expect(peaks.map(\.title) == ["Senate passes sweeping budget bill", "Bridge collapses in the city"])
        #expect(peaks.map(\.hour) == [11, 8])
        #expect(peaks.map(\.outlets) == [15, 8])
        #expect(peaks[0].ids == ["a", "b"])
        #expect(peaks.map(\.phrase) == [nil, "national emergency"])
        #expect(Measure.peaks([]).isEmpty)
    }

    // summaryCountsThresholds reports the period, the stories reaching each count, and the biggest stories.
    @Test func summaryCountsThresholds() {
        let records = [
            record("Senate passes sweeping budget bill", minutes: 0, hour: 12),
            record("Congress declares war after attack", minutes: 5, hour: 21, outlets: 25, phrase: "declares war"),
            record("Mayor opens new library branch", minutes: 5, hour: 3),
        ]
        let text = Measure.summary(records, timeZone: TimeZone(identifier: "UTC")!)
        #expect(text.contains("Period: 2026-11-18 12:00 to 2026-11-18 12:05, 2 refreshes, 40 feeds, 3 stories."))
        #expect(text.contains("    8 outlets: 2 stories, 1 with a top tier phrase\n"))
        #expect(text.contains("   12 outlets: 2 stories, 1 with a top tier phrase\n"))
        #expect(text.contains("   15 outlets: 1 stories, 1 with a top tier phrase\n"))
        #expect(text.contains("   20 outlets: 1 stories, 1 with a top tier phrase\n"))
        #expect(
            text.contains(
                "    21     25  2026-11-18 11:00  Congress declares war after attack (Outlet) [declares war]\n"))
        let lines = text.split(separator: "\n")
        let war = lines.firstIndex { $0.contains("Congress declares war") }
        let library = lines.firstIndex { $0.contains("Mayor opens") }
        #expect(war != nil && library != nil && war! < library!)
    }

    // summaryEmpty says nothing was recorded when there are no records.
    @Test func summaryEmpty() {
        #expect(Measure.summary([]) == "No refreshes recorded yet.\n")
    }
}
