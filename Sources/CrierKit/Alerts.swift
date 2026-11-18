import Foundation

// Sent records one alert so the same event never alerts twice.
public struct Sent: Codable, Sendable, Equatable {
    // keywords are the alerted headline's keywords.
    public let keywords: Set<String>
    // at is when the alert went out.
    public let at: Date

    // init builds a record.
    public init(keywords: Set<String>, at: Date) {
        self.keywords = keywords
        self.at = at
    }
}

// Alerts picks the headlines that deserve an interruption.
public enum Alerts {
    // memory is how long a sent alert keeps its event from alerting again.
    public static let memory: TimeInterval = 48 * 3600

    // major reports whether enough separate outlets carry a headline. A topic the reader wants less of needs
    // twice as many.
    public static func major(_ headline: Headline, rules: AlertRules) -> Bool {
        headline.outlets.count >= rules.minOutlets * headline.interest.majorFactor
    }

    // quiet reports whether the time falls inside quiet hours, which may wrap past midnight.
    public static func quiet(_ now: Date, rules: AlertRules, calendar: Calendar) -> Bool {
        let hour = calendar.component(.hour, from: now)
        if rules.quietStart == rules.quietEnd {
            return false
        }
        if rules.quietStart < rules.quietEnd {
            return hour >= rules.quietStart && hour < rules.quietEnd
        }
        return hour >= rules.quietStart || hour < rules.quietEnd
    }

    // due returns the headlines to alert now, most important first: major, fresh, not already sent, outside
    // quiet hours, and within what is left of today's cap.
    public static func due(
        _ headlines: [Headline], rules: AlertRules, sent: [Sent], now: Date, calendar: Calendar = .current
    ) -> [Headline] {
        guard rules.enabled, !quiet(now, rules: rules, calendar: calendar) else {
            return []
        }
        let today = sent.filter { calendar.isDate($0.at, inSameDayAs: now) }.count
        var left = max(0, rules.dailyCap - today)
        var remembered = sent.filter { now.timeIntervalSince($0.at) < memory }.map(\.keywords)
        var picked: [Headline] = []
        for headline in headlines where left > 0 && major(headline, rules: rules) {
            if let first = headline.first, now.timeIntervalSince(first) > rules.maxAgeHours * 3600 {
                continue
            }
            if remembered.contains(where: { Coverage.same($0, headline.keywords) }) {
                continue
            }
            picked.append(headline)
            remembered.append(headline.keywords)
            left -= 1
        }
        return picked
    }

    // prune drops records older than the memory window.
    public static func prune(_ sent: [Sent], now: Date) -> [Sent] {
        sent.filter { now.timeIntervalSince($0.at) < memory }
    }
}
