import Foundation
import Testing

@testable import CrierKit

// AlertsTests covers the major rule, quiet hours, and which headlines alert.
struct AlertsTests {
    // at returns noon's day at the given UTC hour.
    private func at(_ hour: Int) -> Date {
        utcCalendar.date(bySettingHour: hour, minute: 0, second: 0, of: noon)!
    }

    // major counts outlets against the rules.
    @Test func major() {
        let rules = AlertRules()
        #expect(Alerts.major(headline("Big story about the senate vote", outlets: 6), rules: rules))
        #expect(!Alerts.major(headline("Small story about the senate vote", outlets: 5), rules: rules))
    }

    // quiet handles hours that wrap past midnight, hours within one day, and no quiet hours.
    @Test func quiet() {
        var rules = AlertRules()
        #expect(Alerts.quiet(at(23), rules: rules, calendar: utcCalendar))
        #expect(Alerts.quiet(at(3), rules: rules, calendar: utcCalendar))
        #expect(!Alerts.quiet(at(7), rules: rules, calendar: utcCalendar))
        #expect(!Alerts.quiet(at(12), rules: rules, calendar: utcCalendar))
        rules.quietStart = 13
        rules.quietEnd = 15
        #expect(Alerts.quiet(at(14), rules: rules, calendar: utcCalendar))
        #expect(!Alerts.quiet(at(15), rules: rules, calendar: utcCalendar))
        rules.quietEnd = 13
        #expect(!Alerts.quiet(at(13), rules: rules, calendar: utcCalendar))
    }

    // dueFilters skips minor, stale, and already sent stories, and stops at the daily cap.
    @Test func dueFilters() {
        let fresh = headline("Senate passes sweeping budget bill tonight", outlets: 8)
        let minor = headline("City council approves park bench budget", outlets: 2)
        let stale = headline("Volcano erupts on remote island chain", outlets: 9, hoursAgo: 7)
        let sentBefore = headline("Central bank cuts interest rates again", outlets: 7)
        let second = headline("Earthquake shakes coastal capital city", outlets: 6)
        let third = headline("Rocket carries crew toward lunar orbit", outlets: 6)
        let sent = [
            Sent(keywords: sentBefore.keywords, at: noon.addingTimeInterval(-3600)),
            Sent(keywords: ["old", "story", "words"], at: noon.addingTimeInterval(-7200)),
        ]
        let due = Alerts.due(
            [fresh, minor, stale, sentBefore, second, third], rules: AlertRules(), sent: sent, now: noon,
            calendar: utcCalendar)
        #expect(due == [fresh])
    }

    // dueHonorsSwitchAndQuiet sends nothing when alerts are off or during quiet hours.
    @Test func dueHonorsSwitchAndQuiet() {
        let big = headline("Senate passes sweeping budget bill tonight", outlets: 8)
        var rules = AlertRules()
        rules.enabled = false
        #expect(Alerts.due([big], rules: rules, sent: [], now: noon, calendar: utcCalendar).isEmpty)
        #expect(Alerts.due([big], rules: AlertRules(), sent: [], now: at(23), calendar: utcCalendar).isEmpty)
    }

    // prune forgets alerts older than the memory window.
    @Test func prune() {
        let recent = Sent(keywords: ["a"], at: noon.addingTimeInterval(-3600))
        let old = Sent(keywords: ["b"], at: noon.addingTimeInterval(-Alerts.memory - 1))
        #expect(Alerts.prune([recent, old], now: noon) == [recent])
    }
}
