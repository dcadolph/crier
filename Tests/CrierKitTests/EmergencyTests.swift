import Foundation
import Testing

@testable import CrierKit

// recorded reads a Weather Service response recorded on November 18, 2026. weather-alerts.json holds ten real
// alerts from the past week with their map shapes removed: a tornado warning with its update and its cancel, a
// severe thunderstorm warning, a flash flood warning, a river flood warning, a winter storm warning, a flood
// watch, a small craft advisory, and a tsunami warning sent as a test. weather-none.json is a place with nothing
// in force.
func recorded(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

// EmergencyTests covers decoding Weather Service alerts, the emergency rule, ringing once per warning, and the
// national tiers.
struct EmergencyTests {
    // alerts decodes the recorded alerts.
    private func alerts() throws -> [WeatherAlert] {
        try WeatherAlerts.decode(try recorded("weather-alerts"))
    }

    // find returns the recorded alert with the given event and message type.
    private func find(_ event: String, _ type: String = "Alert") throws -> WeatherAlert {
        try #require(try alerts().first { $0.event == event && $0.messageType == type })
    }

    // decodesRecorded reads every recorded alert and its fields.
    @Test func decodesRecorded() throws {
        let all = try alerts()
        #expect(all.count == 10)
        let tornado = try find("Tornado Warning")
        #expect(tornado.severity == "Extreme")
        #expect(tornado.urgency == "Immediate")
        #expect(tornado.status == "Actual")
        #expect(tornado.phones)
        #expect(tornado.references.isEmpty)
        #expect(tornado.area == "Santa Cruz, CA")
        #expect(tornado.title == "Tornado Warning for Santa Cruz, CA")
        #expect(tornado.until != nil)
        let update = try find("Tornado Warning", "Update")
        #expect(update.references.contains(tornado.id))
        #expect(!update.phones)
        #expect(try find("Flash Flood Warning", "Update").threat == "CONSIDERABLE")
        #expect(try WeatherAlerts.decode(try recorded("weather-none")).isEmpty)
    }

    // decodeSkipsBrokenAlerts drops an alert missing its event and keeps one whose parameters are malformed.
    @Test func decodeSkipsBrokenAlerts() throws {
        let json = #"""
            {"features": [
              {"properties": {"id": "a", "sent": "2026-11-18T12:00:00-06:00"}},
              {"properties": {"id": "b", "event": "Tornado Warning", "sent": "2026-11-18T12:00:00-06:00",
                "parameters": {"WEAHandling": "Imminent Threat"}}}
            ]}
            """#
        let decoded = try WeatherAlerts.decode(Data(json.utf8))
        #expect(decoded.map(\.id) == ["b"])
        #expect(!decoded[0].phones)
    }

    // urgentRecorded counts only the warnings sent to phones or rated Extreme and Immediate. The cancel, the
    // test, the ordinary warnings, the watch, and the advisory never count.
    @Test func urgentRecorded() throws {
        let urgent = try alerts().filter { Emergency.urgent($0, now: $0.sent) }
        #expect(
            urgent.map { "\($0.event) \($0.messageType)" }.sorted() == [
                "Flash Flood Warning Update", "Tornado Warning Alert", "Tornado Warning Update",
            ])
    }

    // notableRecorded counts the watches and ordinary warnings. The urgent warnings, the cancel, the advisory, and
    // the test never count.
    @Test func notableRecorded() throws {
        let notable = try alerts().filter { Emergency.notable($0, now: $0.sent) }
        #expect(
            notable.map(\.event).sorted() == [
                "Flood Warning", "Flood Watch", "Severe Thunderstorm Warning", "Winter Storm Warning",
            ])
    }

    // noticesDropReplaced shows only the latest message of a watch, drops it once canceled, and drops it once it
    // ends.
    @Test func noticesDropReplaced() {
        let watch = WeatherAlert(id: "w1", event: "Flood Watch", sent: noon, expires: noon.addingTimeInterval(7200))
        let update = WeatherAlert(
            id: "w2", event: "Flood Watch", messageType: "Update", sent: noon.addingTimeInterval(600),
            expires: noon.addingTimeInterval(7200), references: ["w1"])
        let cancel = WeatherAlert(
            id: "w3", event: "Flood Watch", messageType: "Cancel", sent: noon.addingTimeInterval(1200),
            references: ["w1", "w2"])
        let advisory = WeatherAlert(id: "a", event: "Wind Advisory", sent: noon)
        let tornado = WeatherAlert(id: "t", event: "Tornado Warning", sent: noon)
        let later = noon.addingTimeInterval(1800)
        #expect(Emergency.notices([watch, advisory, tornado], now: later) == [watch])
        #expect(Emergency.notices([watch, update], now: later) == [update])
        #expect(Emergency.notices([watch, update, cancel], now: later).isEmpty)
        #expect(Emergency.notices([update], now: noon.addingTimeInterval(7200)).isEmpty)
    }

    // sensitivityRecorded sounds for more at the storm and flood sensitivity and for less at the tornado and civil
    // one, and the alerts that stop sounding become notices.
    @Test func sensitivityRecorded() throws {
        let all = try alerts()
        func sounding(_ sensitivity: Sensitivity) -> [String] {
            all.filter { Emergency.urgent($0, now: $0.sent, sensitivity: sensitivity) }
                .map { "\($0.event) \($0.messageType)" }.sorted()
        }
        #expect(
            sounding(.stormAndFlood) == [
                "Flash Flood Warning Update", "Flood Warning Update", "Severe Thunderstorm Warning Alert",
                "Tornado Warning Alert", "Tornado Warning Update",
            ])
        #expect(sounding(.tornadoAndCivil) == ["Tornado Warning Alert", "Tornado Warning Update"])
        let flood = try find("Flash Flood Warning", "Update")
        #expect(Emergency.notable(flood, now: flood.sent, sensitivity: .tornadoAndCivil))
        let storm = try find("Severe Thunderstorm Warning")
        #expect(!Emergency.notable(storm, now: storm.sent, sensitivity: .stormAndFlood))
        let civil = WeatherAlert(id: "c", event: "Shelter In Place Warning", sent: noon)
        #expect(Emergency.urgent(civil, now: noon, sensitivity: .tornadoAndCivil))
        let tsunami = WeatherAlert(id: "t", event: "Tsunami Warning", sent: noon, phones: true)
        #expect(!Emergency.urgent(tsunami, now: noon, sensitivity: .tornadoAndCivil))
    }

    // sensitivityDecodesForgivingly reads each stored choice and falls back to the phone choice for an unknown one.
    @Test func sensitivityDecodesForgivingly() throws {
        func decode(_ json: String) throws -> EmergencyRules {
            try JSONDecoder().decode(EmergencyRules.self, from: Data(json.utf8))
        }
        #expect(try decode("{}").sensitivity == .phone)
        #expect(try decode(#"{"sensitivity": "stormAndFlood"}"#).sensitivity == .stormAndFlood)
        #expect(try decode(#"{"sensitivity": "tornadoAndCivil"}"#).sensitivity == .tornadoAndCivil)
        #expect(try decode(#"{"sensitivity": "everything"}"#).sensitivity == .phone)
        #expect(try decode(#"{"sensitivity": 3}"#).sensitivity == .phone)
    }

    // urgentLifeSafety counts a life-safety event or a catastrophic threat at any rating, and skips an extreme
    // hazard that is not immediate.
    @Test func urgentLifeSafety() {
        let civil = WeatherAlert(id: "c", event: "Civil Danger Warning", sent: noon)
        #expect(Emergency.urgent(civil, now: noon))
        let emergency = WeatherAlert(
            id: "f", event: "Flash Flood Warning", severity: "Severe", urgency: "Immediate", sent: noon,
            threat: "CATASTROPHIC")
        #expect(Emergency.urgent(emergency, now: noon))
        let cold = WeatherAlert(
            id: "x", event: "Extreme Cold Warning", severity: "Extreme", urgency: "Expected", sent: noon)
        #expect(!Emergency.urgent(cold, now: noon))
        let exercise = WeatherAlert(id: "e", event: "Civil Danger Warning", status: "Exercise", sent: noon)
        #expect(!Emergency.urgent(exercise, now: noon))
    }

    // urgentEnds stops counting a warning once it ends.
    @Test func urgentEnds() throws {
        let tornado = try find("Tornado Warning")
        let until = try #require(tornado.until)
        #expect(Emergency.urgent(tornado, now: until.addingTimeInterval(-1)))
        #expect(!Emergency.urgent(tornado, now: until))
        let open = WeatherAlert(id: "o", event: "Tornado Warning", sent: noon)
        #expect(Emergency.urgent(open, now: noon.addingTimeInterval(86400)))
    }

    // ringOncePerWarning rings a new warning once, keeps its update quiet, and rings a different warning.
    @Test func ringOncePerWarning() throws {
        let tornado = try find("Tornado Warning")
        let update = try find("Tornado Warning", "Update")
        let flood = try find("Flash Flood Warning", "Update")
        let first = Emergency.ring([tornado], heard: [])
        #expect(first.ring == [tornado])
        let second = Emergency.ring([update, tornado], heard: first.heard)
        #expect(second.ring.isEmpty)
        let third = Emergency.ring([flood, update], heard: second.heard)
        #expect(third.ring == [flood])
        #expect(Emergency.ring([update], heard: []).ring == [update])
    }

    // active keeps the urgent warnings, newest first.
    @Test func activeNewestFirst() throws {
        let early = WeatherAlert(id: "t1", event: "Tornado Warning", sent: noon)
        let late = WeatherAlert(id: "t2", event: "Tornado Warning", sent: noon.addingTimeInterval(600))
        let watch = WeatherAlert(id: "w", event: "Tornado Watch", sent: noon.addingTimeInterval(1200))
        #expect(Emergency.active([early, watch, late], now: noon.addingTimeInterval(1800)) == [late, early])
    }

    // activeDropsReplaced follows the recorded tornado chain: the update replaces the warning, and the cancel
    // clears it at once rather than when the warning would have ended.
    @Test func activeDropsReplaced() throws {
        let tornado = try find("Tornado Warning")
        let update = try find("Tornado Warning", "Update")
        let cancel = try find("Tornado Warning", "Cancel")
        #expect(Emergency.active([tornado, update], now: update.sent) == [update])
        #expect(Emergency.active([tornado, cancel], now: tornado.sent) == [tornado])
        let until = try #require(tornado.until)
        #expect(cancel.sent < until)
        #expect(Emergency.active([tornado, update, cancel], now: cancel.sent).isEmpty)
        let open = WeatherAlert(id: "o", event: "Tornado Warning", sent: noon)
        #expect(Emergency.active([open, tornado, update, cancel], now: cancel.sent) == [open])
    }

    // tierCountsOutletsAndPhrases turns a wide story red, and sounds only for a top tier phrase.
    @Test func tierCountsOutletsAndPhrases() {
        let rules = NationalRules()
        #expect(Emergency.tier(headline("Senate passes sweeping budget bill", outlets: 12), rules: rules) == .red)
        #expect(Emergency.tier(headline("Senate passes sweeping budget bill", outlets: 11), rules: rules) == .none)
        #expect(Emergency.tier(headline("U.S. Declares War on Rival Power", outlets: 12), rules: rules) == .top)
        #expect(Emergency.tier(headline("President declares a national emergency", outlets: 6), rules: rules) == .none)
        #expect(Emergency.tier(headline("Warlords declares warming truce", outlets: 12), rules: rules) == .red)
    }

    // nationalLoudestFirst keeps fresh red and top stories, loudest first, and drops stale and small ones.
    @Test func nationalLoudestFirst() {
        let rules = NationalRules()
        let red = headline("Senate passes sweeping budget bill", outlets: 12)
        let top = headline("Congress declares war after attack", outlets: 12)
        let small = headline("Mayor opens new library branch", outlets: 3)
        let stale = headline("Nation declares martial law overnight", outlets: 14, hoursAgo: 4)
        let picked = Emergency.national([red, small, stale, top], rules: rules, now: noon)
        #expect(picked.map(\.0) == [top, red])
        #expect(picked.map(\.1) == [.top, .red])
    }

    // outletsWithinWindow counts only the outlets that carried a story within the window after its first report.
    @Test func outletsWithinWindow() {
        let early = (0..<4).map { story("Bridge collapses in the city", outlet: "Early \($0)", hoursAgo: 3) }
        let late = (0..<4).map { story("Bridge collapses in the city", outlet: "Late \($0)", hoursAgo: 1) }
        let undated = story("Bridge collapses in the city", outlet: "Undated", hoursAgo: nil)
        let all = early + late + [undated]
        let event = Headline(lead: all[0], stories: all, outlets: all.map(\.outlet).sorted(), keywords: [])
        #expect(Emergency.outletsWithin(event, window: 3600) == 4)
        #expect(Emergency.outletsWithin(event, window: 7200) == 8)
    }

    // spotMeters measures the distance between spots: zero to itself, about 111 kilometers for a degree of latitude,
    // and about 1.1 kilometers for a hundredth of a degree.
    @Test func spotMeters() {
        let austin = Spot(latitude: 30.267, longitude: -97.743)
        #expect(austin.meters(to: austin) == 0)
        let north = Spot(latitude: 31.267, longitude: -97.743)
        #expect(abs(austin.meters(to: north) - 111_195) < 50)
        let step = Spot(latitude: 30.277, longitude: -97.743)
        #expect(abs(step.meters(to: austin) - 1112) < 5)
    }

    // spotRounds keeps three decimals and writes the Weather Service point.
    @Test func spotRounds() {
        let spot = Spot(latitude: 38.901234, longitude: -77.045678)
        #expect(spot.point == "38.901,-77.046")
        #expect(
            EmergencyFeed.url(for: spot).absoluteString == "https://api.weather.gov/alerts/active?point=38.901,-77.046")
    }
}

// EmergencyFeedTests covers checking the Weather Service with a recorded response.
@MainActor
struct EmergencyFeedTests {
    // Reads counts fetches and fails on request.
    final class Reads: @unchecked Sendable {
        // data is the response, or nil to fail.
        var data: Data?
        // urls are the addresses read.
        var urls: [URL] = []
    }

    // feed builds a feed that answers from reads.
    private func feed(_ reads: Reads) -> EmergencyFeed {
        EmergencyFeed(spot: Spot(latitude: 37, longitude: -122)) { url in
            reads.urls.append(url)
            guard let data = reads.data else {
                throw URLError(.notConnectedToInternet)
            }
            return data
        }
    }

    // firstWarning returns the recorded tornado warning that went to phones.
    private func firstWarning(_ reads: Reads) throws -> WeatherAlert {
        let data = try #require(reads.data)
        return try #require(try WeatherAlerts.decode(data).first { $0.messageType == "Alert" && $0.phones })
    }

    // checkRingsOnce keeps the urgent warnings and rings once for them.
    @Test func checkRingsOnce() async throws {
        let reads = Reads()
        reads.data = try recorded("weather-alerts")
        let feed = feed(reads)
        var rung: [[WeatherAlert]] = []
        feed.onRing = { rung.append($0) }
        let tornado = try firstWarning(reads)
        await feed.check(now: tornado.sent)
        #expect(feed.alerts.contains(tornado))
        #expect(feed.failure == nil)
        #expect(rung.count == 1)
        await feed.check(now: tornado.sent)
        #expect(rung.count == 1)
        #expect(reads.urls.first?.query == "point=37.0,-122.0")
    }

    // checkKeepsNotices keeps the watches and ordinary warnings in force without ringing for them.
    @Test func checkKeepsNotices() async throws {
        let reads = Reads()
        reads.data = try recorded("weather-alerts")
        let feed = feed(reads)
        var rung: [[WeatherAlert]] = []
        feed.onRing = { rung.append($0) }
        let now = try #require(ISO8601DateFormatter().date(from: "2026-11-18T18:00:00-08:00"))
        await feed.check(now: now)
        #expect(Set(feed.notices.map(\.event)) == ["Flood Warning", "Flood Watch", "Winter Storm Warning"])
        #expect(feed.alerts.map(\.event) == ["Flash Flood Warning"])
        #expect(rung.map { $0.map(\.event) } == [["Flash Flood Warning"]])
        reads.data = nil
        await feed.check(now: now.addingTimeInterval(60))
        #expect(feed.notices.count == 3)
        feed.spot = Spot(latitude: 30, longitude: -97)
        #expect(feed.notices.isEmpty)
    }

    // sensitivityMovesAlerts moves the flash flood warning from the warnings to the notices at the tornado and civil
    // sensitivity, and keeps it there through a failed read.
    @Test func sensitivityMovesAlerts() async throws {
        let reads = Reads()
        reads.data = try recorded("weather-alerts")
        let feed = feed(reads)
        feed.sensitivity = .tornadoAndCivil
        var rung: [[WeatherAlert]] = []
        feed.onRing = { rung.append($0) }
        let now = try #require(ISO8601DateFormatter().date(from: "2026-11-18T18:00:00-08:00"))
        await feed.check(now: now)
        #expect(feed.alerts.isEmpty)
        #expect(feed.notices.map(\.event).contains("Flash Flood Warning"))
        #expect(rung.isEmpty)
        reads.data = nil
        feed.sensitivity = .phone
        await feed.check(now: now.addingTimeInterval(60))
        #expect(feed.alerts.map(\.event) == ["Flash Flood Warning"])
        #expect(!feed.notices.map(\.event).contains("Flash Flood Warning"))
    }

    // moveKeepsHeard never rings again for a warning heard before the spot moved.
    @Test func moveKeepsHeard() async throws {
        let reads = Reads()
        reads.data = try recorded("weather-alerts")
        let feed = feed(reads)
        var rung = 0
        feed.onRing = { _ in rung += 1 }
        let tornado = try firstWarning(reads)
        await feed.check(now: tornado.sent)
        #expect(rung == 1)
        feed.spot = Spot(latitude: 37.01, longitude: -122)
        #expect(feed.alerts.isEmpty)
        await feed.check(now: tornado.sent)
        #expect(feed.alerts.contains(tornado))
        #expect(rung == 1)
    }

    // failedCheckKeepsWarnings keeps the known warnings through a failed read until they end.
    @Test func failedCheckKeepsWarnings() async throws {
        let reads = Reads()
        reads.data = try recorded("weather-alerts")
        let feed = feed(reads)
        let tornado = try firstWarning(reads)
        await feed.check(now: tornado.sent)
        reads.data = nil
        await feed.check(now: tornado.sent.addingTimeInterval(60))
        #expect(feed.alerts.contains(tornado))
        #expect(feed.failure != nil)
        await feed.check(now: try #require(tornado.until))
        #expect(!feed.alerts.contains(tornado))
    }

    // noSpotChecksNothing reads nothing until a place is known, and a new place clears the old warnings.
    @Test func noSpotChecksNothing() async throws {
        let reads = Reads()
        reads.data = try recorded("weather-alerts")
        let feed = feed(reads)
        feed.spot = nil
        await feed.check()
        #expect(reads.urls.isEmpty)
        feed.spot = Spot(latitude: 37, longitude: -122)
        let tornado = try firstWarning(reads)
        await feed.check(now: tornado.sent)
        #expect(!feed.alerts.isEmpty)
        feed.spot = Spot(latitude: 30, longitude: -97)
        #expect(feed.alerts.isEmpty)
    }
}
