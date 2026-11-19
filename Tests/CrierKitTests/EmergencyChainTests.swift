import Foundation
import Testing

@testable import CrierKit

// EmergencyChainTests covers warnings as chains of messages, using real Weather Service chains recorded on November
// 19, 2026 with their map shapes removed. chain-flood-kfgz.json is flash flood warning KFGZ.FF.W.0220: an Alert
// sent to phones and three updates that keep a considerable threat without the phone flag. chain-flood-kmtr.json
// is flash flood warning KMTR.FF.W.0002 from its Alert to its cancel, where each update references only the one
// before it. chain-storm-exp.json is a severe thunderstorm warning and its expiration statement typed Alert.
// chain-tornado-exp.json holds two tornado warning expiration statements typed Update. chain-winter-con.json is a
// winter storm warning continuation typed Alert whose earlier message moved to the expired references.
struct EmergencyChainTests {
    // load decodes a recorded chain, oldest first.
    private func load(_ name: String) throws -> [WeatherAlert] {
        try WeatherAlerts.decode(try recorded(name)).sorted { $0.sent < $1.sent }
    }

    // copy rebuilds a recorded alert under a new identifier with the given threat and references.
    private func copy(
        _ alert: WeatherAlert, id: String, threat: String?, references: [String]
    ) -> WeatherAlert {
        WeatherAlert(
            id: id, event: alert.event, headline: alert.headline, area: alert.area, severity: alert.severity,
            urgency: alert.urgency, status: alert.status, messageType: "Update", sent: alert.sent,
            expires: alert.expires, ends: alert.ends, references: references, phones: false, threat: threat,
            vtec: alert.vtec)
    }

    // decodesChainFields reads the coded event lines, the chain, the expired references, and every damage threat.
    @Test func decodesChainFields() throws {
        let flood = try load("chain-flood-kfgz")
        #expect(flood.count == 4)
        #expect(flood[0].vtec == ["/O.NEW.KFGZ.FF.W.0220.261117T2221Z-261118T0415Z/"])
        #expect(flood.map(\.actions) == [["NEW"], ["CON"], ["CON"], ["CON"]])
        #expect(flood.allSatisfy { $0.chain == "KFGZ.FF.W.0220" })
        #expect(flood.allSatisfy { $0.threat == "CONSIDERABLE" && !$0.ended })
        let storm = try load("chain-storm-exp")
        #expect(storm[1].ended)
        #expect(storm[1].chain == "KEPZ.SV.W.0236")
        #expect(storm[1].expiredReferences == [storm[0].id])
        let con = try #require(try load("chain-winter-con").first)
        #expect(con.chain == "KLKN.WS.W.0003")
        #expect(con.expiredReferences == ["urn:oid:2.49.0.1.840.0.de131009f122f224a621ff41d1a6f7b9b6bf78f3.001.1"])
        let sample = try WeatherAlerts.decode(try recorded("weather-alerts"))
        let winter = try #require(sample.first { $0.event == "Winter Storm Warning" })
        #expect(winter.expiredReferences.count == 9)
        #expect(winter.expiredReferences.allSatisfy { $0.hasPrefix("urn:oid:") })
        let thunder = try #require(sample.first { $0.event == "Severe Thunderstorm Warning" })
        #expect(thunder.stormThreat == "CONSIDERABLE")
        #expect(WeatherAlert(id: "x", event: "Special Weather Statement", sent: noon).chain == nil)
    }

    // updatesStayPhoneLevel keeps every message of a real considerable flash flood warning urgent after the phone
    // flag drops, and counts the other damage threats phones alert for.
    @Test func updatesStayPhoneLevel() throws {
        let chain = try load("chain-flood-kfgz")
        #expect(chain[0].phones)
        #expect(chain.dropFirst().allSatisfy { !$0.phones })
        for alert in chain {
            let now = alert.sent.addingTimeInterval(60)
            #expect(Emergency.active([alert], now: now) == [alert])
            #expect(Emergency.notices([alert], now: now).isEmpty)
        }
        let tornado = WeatherAlert(id: "t", event: "Tornado Warning", sent: noon, threat: "CONSIDERABLE")
        #expect(Emergency.phoneLevel(tornado))
        let destructive = WeatherAlert(
            id: "d", event: "Severe Thunderstorm Warning", sent: noon, stormThreat: "DESTRUCTIVE")
        #expect(Emergency.urgent(destructive, now: noon))
        let considerable = WeatherAlert(
            id: "c", event: "Severe Thunderstorm Warning", sent: noon, stormThreat: "CONSIDERABLE")
        #expect(!Emergency.urgent(considerable, now: noon))
        let base = WeatherAlert(id: "b", event: "Flash Flood Warning", sent: noon)
        #expect(!Emergency.urgent(base, now: noon))
    }

    // endedStatementsDrop keeps cancel and expiration statements out of force whatever their message type, even
    // when their chain already sounded.
    @Test func endedStatementsDrop() throws {
        let storm = try load("chain-storm-exp")
        let exp = storm[1]
        #expect(exp.messageType == "Alert")
        let now = exp.sent.addingTimeInterval(20)
        #expect(!Emergency.inForce(exp, now: now))
        let heard = Emergency.ring([storm[0]], heard: []).heard
        #expect(heard.contains("KEPZ.SV.W.0236"))
        #expect(Emergency.active([exp], now: now, sensitivity: .stormAndFlood, heard: heard).isEmpty)
        #expect(Emergency.notices([exp], now: now, heard: heard).isEmpty)
        for tornado in try load("chain-tornado-exp") {
            #expect(tornado.messageType == "Update")
            #expect(!Emergency.urgent(tornado, now: tornado.sent.addingTimeInterval(60)))
        }
        let cancel = try #require(try load("chain-flood-kmtr").last)
        #expect(cancel.actions == ["CAN"])
        #expect(!Emergency.inForce(cancel, now: cancel.sent))
        let mixed = WeatherAlert(
            id: "m", event: "Flood Warning", sent: noon,
            vtec: [
                "/O.EXP.KMLB.FL.W.0002.000000T0000Z-261118T1200Z/", "/O.NEW.KMLB.FL.W.0004.261118T1200Z-000000T0000Z/",
            ])
        #expect(Emergency.inForce(mixed, now: noon))
        #expect(mixed.chain == "KMLB.FL.W.0004")
    }

    // ringOncePerChain keeps every later message of a warning quiet, even when its references skip the message
    // that rang, it arrives typed Alert with no references, or its earlier message moved to the expired references.
    @Test func ringOncePerChain() throws {
        let kmtr = try load("chain-flood-kmtr")
        let first = Emergency.ring([kmtr[0]], heard: [])
        #expect(first.ring == [kmtr[0]])
        #expect(first.heard.contains("KMTR.FF.W.0002"))
        let last = kmtr[4]
        #expect(last.phones)
        #expect(!last.references.contains(kmtr[0].id))
        #expect(Emergency.ring([last], heard: first.heard).ring.isEmpty)
        let con = try #require(try load("chain-winter-con").first)
        #expect(con.messageType == "Alert")
        #expect(con.references.isEmpty)
        #expect(Emergency.ring([con], heard: Set(con.expiredReferences)).ring.isEmpty)
        #expect(Emergency.ring([con], heard: ["KLKN.WS.W.0003"]).ring.isEmpty)
        #expect(Emergency.ring([con], heard: []).ring == [con])
        let storm = try load("chain-storm-exp")
        #expect(Emergency.ring([storm[1]], heard: [storm[0].id]).ring.isEmpty)
    }

    // catastrophicRingsAgain rings a warning that already sounded once more when an update raises its threat to
    // catastrophic, and only once.
    @Test func catastrophicRingsAgain() throws {
        let chain = try load("chain-flood-kfgz")
        let first = Emergency.ring([chain[0]], heard: [])
        #expect(first.ring == [chain[0]])
        #expect(Emergency.ring([chain[1]], heard: first.heard).ring.isEmpty)
        let emergency = copy(chain[1], id: "emergency", threat: "CATASTROPHIC", references: [chain[0].id])
        let raised = Emergency.ring([emergency], heard: first.heard)
        #expect(raised.ring == [emergency])
        let next = copy(
            chain[2], id: "next", threat: "CATASTROPHIC", references: [chain[0].id, emergency.id])
        #expect(Emergency.ring([next], heard: raised.heard).ring.isEmpty)
        let lower = copy(chain[3], id: "lower", threat: "CONSIDERABLE", references: [])
        #expect(Emergency.ring([lower], heard: raised.heard).ring.isEmpty)
        let fresh = Emergency.ring([emergency], heard: [])
        #expect(fresh.ring == [emergency])
        #expect(Emergency.ring([next], heard: fresh.heard).ring.isEmpty)
    }

    // heardChainStaysRed keeps a warning that already sounded red on an update that lost the phone flag, and drops
    // it once its chain expires.
    @Test func heardChainStaysRed() {
        let squall = WeatherAlert(
            id: "s1", event: "Snow Squall Warning", sent: noon, expires: noon.addingTimeInterval(3600), phones: true,
            vtec: ["/O.NEW.KCTP.SQ.W.0010.261118T1200Z-261118T1300Z/"])
        let update = WeatherAlert(
            id: "s2", event: "Snow Squall Warning", messageType: "Update", sent: noon.addingTimeInterval(600),
            expires: noon.addingTimeInterval(3600), references: ["s1"],
            vtec: ["/O.CON.KCTP.SQ.W.0010.000000T0000Z-261118T1300Z/"])
        let expired = WeatherAlert(
            id: "s3", event: "Snow Squall Warning", sent: noon.addingTimeInterval(1200),
            expires: noon.addingTimeInterval(3600), vtec: ["/O.EXP.KCTP.SQ.W.0010.000000T0000Z-261118T1300Z/"])
        let later = noon.addingTimeInterval(900)
        #expect(Emergency.active([update], now: later).isEmpty)
        #expect(Emergency.notices([update], now: later) == [update])
        let heard = Emergency.ring(Emergency.active([squall], now: noon), heard: []).heard
        #expect(Emergency.active([update], now: later, heard: heard) == [update])
        #expect(Emergency.notices([update], now: later, heard: heard).isEmpty)
        #expect(Emergency.ring([update], heard: heard).ring.isEmpty)
        let end = noon.addingTimeInterval(1500)
        #expect(Emergency.active([expired], now: end, heard: heard).isEmpty)
        #expect(Emergency.notices([expired], now: end, heard: heard).isEmpty)
    }

    // dangerFirst puts tornado and life-safety alerts first, then other phone-level alerts, then the rest, newest
    // first within each rank, in active, notices, and ring.
    @Test func dangerFirst() {
        let tornado = WeatherAlert(id: "t", event: "Tornado Warning", sent: noon)
        let flood = WeatherAlert(
            id: "f", event: "Flash Flood Warning", sent: noon.addingTimeInterval(600), threat: "CONSIDERABLE")
        let storm = WeatherAlert(id: "s", event: "Severe Thunderstorm Warning", sent: noon.addingTimeInterval(1200))
        let now = noon.addingTimeInterval(1800)
        #expect(
            Emergency.active([storm, flood, tornado], now: now, sensitivity: .stormAndFlood) == [tornado, flood, storm])
        #expect(Emergency.ring([flood, tornado], heard: []).ring == [tornado, flood])
        let tornadoWatch = WeatherAlert(id: "tw", event: "Tornado Watch", sent: noon)
        let floodWatch = WeatherAlert(id: "fw", event: "Flood Watch", sent: noon.addingTimeInterval(600))
        #expect(Emergency.notices([floodWatch, tornadoWatch], now: now) == [tornadoWatch, floodWatch])
    }

    // emergencyEventsShow shows an event ending in Emergency at least as a quiet line, and never a statement.
    @Test func emergencyEventsShow() {
        let local = WeatherAlert(id: "l", event: "Local Area Emergency", sent: noon)
        #expect(Emergency.notable(local, now: noon))
        #expect(Emergency.notices([local], now: noon) == [local])
        let abduction = WeatherAlert(id: "a", event: "Child Abduction Emergency", sent: noon)
        #expect(Emergency.urgent(abduction, now: noon))
        #expect(Emergency.notable(abduction, now: noon, sensitivity: .tornadoAndCivil))
        let canceled = WeatherAlert(id: "c", event: "Local Area Emergency", messageType: "Cancel", sent: noon)
        #expect(!Emergency.notable(canceled, now: noon))
        let statement = WeatherAlert(id: "s", event: "Special Weather Statement", sent: noon)
        #expect(!Emergency.notable(statement, now: noon))
    }
}
