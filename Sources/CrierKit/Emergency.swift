import Foundation

// WeatherAlert is one alert from the National Weather Service, as api.weather.gov serves it.
public struct WeatherAlert: Sendable, Hashable, Identifiable {
    // id is the alert's own identifier. Every update to a warning gets a new one.
    public let id: String
    // event names the alert, such as "Tornado Warning".
    public let event: String
    // headline is the Weather Service's one line summary, if it sent one.
    public let headline: String?
    // area lists the counties or zones covered, in the Weather Service's words.
    public let area: String
    // severity is Extreme, Severe, Moderate, Minor, or Unknown.
    public let severity: String
    // urgency is Immediate, Expected, Future, Past, or Unknown.
    public let urgency: String
    // status is Actual for a real alert, or Exercise, System, Test, or Draft.
    public let status: String
    // messageType is Alert for a new warning, Update for a change to one, or Cancel.
    public let messageType: String
    // sent is when the Weather Service sent the alert.
    public let sent: Date
    // expires is when this message stops being current.
    public let expires: Date?
    // ends is when the hazard itself is expected to end, if the Weather Service said.
    public let ends: Date?
    // references are the identifiers of the earlier alerts this one updates or cancels.
    public let references: [String]
    // expiredReferences are the identifiers of earlier alerts in the same warning that expired before this one
    // was sent. The Weather Service moves them out of references, so an alert can name its earlier messages only
    // here.
    public let expiredReferences: [String]
    // phones reports whether the Weather Service sent the alert to phones as an imminent threat. The Weather
    // Service sets it only on the first message of a warning, never on its updates.
    public let phones: Bool
    // threat is the tornado or flash flood damage threat the Weather Service attached, CONSIDERABLE or
    // CATASTROPHIC. When an alert carries both, CATASTROPHIC wins.
    public let threat: String?
    // stormThreat is the thunderstorm damage threat the Weather Service attached, CONSIDERABLE or DESTRUCTIVE.
    public let stormThreat: String?
    // vtec are the alert's coded event lines, such as "/O.CON.KFGZ.FF.W.0220.000000T0000Z-261118T0415Z/". An
    // alert can carry several, and alerts outside the weather warning system carry none.
    public let vtec: [String]
    // instruction tells people what to do, if the Weather Service said.
    public let instruction: String?
    // link is the alert's page on api.weather.gov.
    public let link: URL?

    // init builds an alert.
    public init(
        id: String, event: String, headline: String? = nil, area: String = "", severity: String = "Unknown",
        urgency: String = "Unknown", status: String = "Actual", messageType: String = "Alert", sent: Date,
        expires: Date? = nil, ends: Date? = nil, references: [String] = [], expiredReferences: [String] = [],
        phones: Bool = false, threat: String? = nil, stormThreat: String? = nil, vtec: [String] = [],
        instruction: String? = nil, link: URL? = nil
    ) {
        self.id = id
        self.event = event
        self.headline = headline
        self.area = area
        self.severity = severity
        self.urgency = urgency
        self.status = status
        self.messageType = messageType
        self.sent = sent
        self.expires = expires
        self.ends = ends
        self.references = references
        self.expiredReferences = expiredReferences
        self.phones = phones
        self.threat = threat
        self.stormThreat = stormThreat
        self.vtec = vtec
        self.instruction = instruction
        self.link = link
    }

    // until is when the alert stops being in force: when the hazard ends, or when the message expires.
    public var until: Date? {
        ends ?? expires
    }

    // title is what the ticker shows: the event and the area it covers.
    public var title: String {
        area.isEmpty ? event : "\(event) for \(area)"
    }

    // actions are the actions of the coded event lines, such as NEW, CON, EXT, CAN, or EXP, one per line.
    public var actions: [String] {
        vtec.compactMap { Self.fields($0)?[1] }
    }

    // ended reports whether every coded event line cancels or expires its event, so the alert only announces that
    // a warning is over. An alert with no coded event lines never counts as ended.
    public var ended: Bool {
        let actions = actions
        return !actions.isEmpty && actions.allSatisfy(Self.endings.contains)
    }

    // chain names the warning this alert belongs to as office.phenomenon.significance.eventNumber, such as
    // "KFGZ.FF.W.0220". Every message about one warning shares it, whatever its type or references. It comes from
    // the first coded event line still in force, or the first line when all have ended, and is nil when the alert
    // has none.
    public var chain: String? {
        let lines = vtec.compactMap(Self.fields)
        guard let line = lines.first(where: { !Self.endings.contains($0[1]) }) ?? lines.first else {
            return nil
        }
        return line[2...5].joined(separator: ".")
    }

    // catastrophic reports whether the alert carries a catastrophic tornado or flash flood damage threat, as a
    // tornado emergency or a flash flood emergency does.
    public var catastrophic: Bool {
        threat == "CATASTROPHIC"
    }

    // keys are every name this alert answers to when checking whether it already sounded: its own identifier,
    // the identifiers it references, the expired ones it names, and its chain.
    var keys: Set<String> {
        Set([id] + references + expiredReferences + (chain.map { [$0] } ?? []))
    }

    // endings are the coded event actions that end an event: CAN for canceled, EXP for expired, and UPG for
    // replaced by a stronger event, which arrives on its own coded line.
    static let endings: Set<String> = ["CAN", "EXP", "UPG"]

    // fields splits a coded event line into its parts: class, action, office, phenomenon, significance, event
    // number, and times. It returns nil for a line too short to hold an event number.
    static func fields(_ line: String) -> [String]? {
        let fields = line.trimmingCharacters(in: CharacterSet(charactersIn: "/ ")).split(separator: ".")
            .map(String.init)
        return fields.count >= 6 ? fields : nil
    }
}

// WeatherAlerts decodes an api.weather.gov alert collection.
public enum WeatherAlerts {
    // decode reads the GeoJSON collection and skips any alert missing its id, event, or send time.
    public static func decode(_ data: Data) throws -> [WeatherAlert] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Collection.self, from: data).features.compactMap(\.properties.alert)
    }

    // Collection is the GeoJSON wrapper.
    private struct Collection: Decodable {
        let features: [Feature]
    }

    // Feature holds one alert's properties.
    private struct Feature: Decodable {
        let properties: Properties
    }

    // Reference points at an earlier alert.
    private struct Reference: Decodable {
        let identifier: String
    }

    // Properties are the alert fields Crier reads. Every field is optional so one odd alert never sinks the
    // whole collection.
    private struct Properties: Decodable {
        let id: String?
        let event: String?
        let headline: String?
        let areaDesc: String?
        let severity: String?
        let urgency: String?
        let status: String?
        let messageType: String?
        let sent: Date?
        let expires: Date?
        let ends: Date?
        let references: [Reference]?
        let parameters: [String: [String]]?
        let instruction: String?

        // CodingKeys names the decoded fields.
        private enum CodingKeys: String, CodingKey {
            case id, event, headline, areaDesc, severity, urgency, status, messageType, sent, expires, ends
            case references, parameters, instruction
        }

        // init decodes each field on its own, so a malformed value drops only that field, never the alert.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try? c.decodeIfPresent(String.self, forKey: .id)
            event = try? c.decodeIfPresent(String.self, forKey: .event)
            headline = try? c.decodeIfPresent(String.self, forKey: .headline)
            areaDesc = try? c.decodeIfPresent(String.self, forKey: .areaDesc)
            severity = try? c.decodeIfPresent(String.self, forKey: .severity)
            urgency = try? c.decodeIfPresent(String.self, forKey: .urgency)
            status = try? c.decodeIfPresent(String.self, forKey: .status)
            messageType = try? c.decodeIfPresent(String.self, forKey: .messageType)
            sent = try? c.decodeIfPresent(Date.self, forKey: .sent)
            expires = try? c.decodeIfPresent(Date.self, forKey: .expires)
            ends = try? c.decodeIfPresent(Date.self, forKey: .ends)
            references = try? c.decodeIfPresent([WeatherAlerts.Reference].self, forKey: .references)
            parameters = try? c.decodeIfPresent([String: [String]].self, forKey: .parameters)
            instruction = try? c.decodeIfPresent(String.self, forKey: .instruction)
        }

        // alert is the decoded alert, or nil when a required field is missing.
        var alert: WeatherAlert? {
            guard let id, let event, let sent else {
                return nil
            }
            let threats = ["tornadoDamageThreat", "flashFloodDamageThreat"].compactMap { parameters?[$0]?.first }
            return WeatherAlert(
                id: id, event: event, headline: headline, area: areaDesc ?? "", severity: severity ?? "Unknown",
                urgency: urgency ?? "Unknown", status: status ?? "Actual", messageType: messageType ?? "Alert",
                sent: sent, expires: expires, ends: ends, references: references?.map(\.identifier) ?? [],
                expiredReferences: expired, phones: parameters?["WEAHandling"]?.contains("Imminent Threat") ?? false,
                threat: threats.first { $0 == "CATASTROPHIC" } ?? threats.first,
                stormThreat: parameters?["thunderstormDamageThreat"]?.first, vtec: parameters?["VTEC"] ?? [],
                instruction: instruction, link: URL(string: id))
        }

        // expired reads the identifiers out of the expiredReferences parameter. Each value holds entries separated
        // by spaces, and each entry is the sender, the identifier, and the send time, separated by commas.
        var expired: [String] {
            (parameters?["expiredReferences"] ?? []).flatMap { $0.split(separator: " ") }.compactMap { entry in
                let parts = entry.split(separator: ",", omittingEmptySubsequences: false)
                return parts.count >= 2 && !parts[1].isEmpty ? String(parts[1]) : nil
            }
        }
    }
}

// Tier is how loudly an emergency interrupts.
public enum Tier: Int, Sendable, Comparable {
    // none leaves the ticker as it is.
    case none
    // orange pins a quiet line for a watch or an ordinary warning, with no sound and no flashing.
    case orange
    // red turns the ticker red, with no sound and no flashing.
    case red
    // top turns the ticker red, flashes it, and plays the emergency sound.
    case top

    // < orders tiers from quiet to loud.
    public static func < (a: Tier, b: Tier) -> Bool {
        a.rawValue < b.rawValue
    }
}

// Emergency decides which Weather Service alerts and which national stories count as emergencies.
public enum Emergency {
    // lifeSafety are the events that always count, even when the Weather Service rates them lower or does not
    // send them to phones. They are the warnings that tell people to act now to stay alive.
    public static let lifeSafety: Set<String> = [
        "Tornado Warning", "Extreme Wind Warning", "Tsunami Warning", "Civil Danger Warning",
        "Civil Emergency Message", "Shelter In Place Warning", "Evacuation Immediate", "Law Enforcement Warning",
        "Child Abduction Emergency", "Nuclear Power Plant Warning", "Radiological Hazard Warning",
        "Hazardous Materials Warning", "Earthquake Warning",
    ]

    // civil are the tornado and civil emergency events, the only ones that sound at the narrowest sensitivity.
    public static let civil: Set<String> = [
        "Tornado Warning", "Civil Danger Warning", "Civil Emergency Message", "Shelter In Place Warning",
        "Evacuation Immediate", "Law Enforcement Warning", "Nuclear Power Plant Warning", "Radiological Hazard Warning",
        "Hazardous Materials Warning",
    ]

    // phoneLevel reports whether an alert is one a phone in the area alerts for. It went to phones as an imminent
    // threat, is rated Extreme and Immediate, is one of the life-safety events, or carries a considerable or
    // catastrophic tornado or flash flood damage threat or a destructive thunderstorm damage threat. The Weather
    // Service flags only the first message of a warning for phones, and the damage threat keeps its updates at
    // this level.
    public static func phoneLevel(_ alert: WeatherAlert) -> Bool {
        alert.phones || (alert.severity == "Extreme" && alert.urgency == "Immediate")
            || lifeSafety.contains(alert.event) || ["CONSIDERABLE", "CATASTROPHIC"].contains(alert.threat)
            || alert.stormThreat == "DESTRUCTIVE"
    }

    // urgent reports whether an alert in force now sounds at the given sensitivity. It has to be a real alert, not
    // a cancel or an expiration, and not past its end. At the phone sensitivity it must be at the phone level.
    // The storm and flood sensitivity adds severe thunderstorm and flood warnings. The tornado and civil
    // sensitivity counts only the civil events. Watches, advisories, and statements never count.
    public static func urgent(_ alert: WeatherAlert, now: Date, sensitivity: Sensitivity = .phone) -> Bool {
        guard inForce(alert, now: now) else {
            return false
        }
        switch sensitivity {
        case .phone:
            return phoneLevel(alert)
        case .stormAndFlood:
            return phoneLevel(alert) || alert.event == "Severe Thunderstorm Warning"
                || alert.event.hasSuffix("Flood Warning")
        case .tornadoAndCivil:
            return civil.contains(alert.event)
        }
    }

    // sounds reports whether an alert in force now stays red: it is urgent at the given sensitivity, or it belongs
    // to a warning whose chain is in heard, since that warning already sounded on this Mac.
    static func sounds(_ alert: WeatherAlert, now: Date, sensitivity: Sensitivity, heard: Set<String>) -> Bool {
        if urgent(alert, now: now, sensitivity: sensitivity) {
            return true
        }
        guard let chain = alert.chain, heard.contains(chain) else {
            return false
        }
        return inForce(alert, now: now)
    }

    // notable reports whether an alert in force now shows as a quiet line because it does not sound at the given
    // sensitivity and its chain is not in heard. It must be a watch, a warning, or an event ending in Emergency,
    // such as a Severe Thunderstorm Warning, a Flood Watch, or a Local Area Emergency. Advisories and statements
    // never count.
    public static func notable(
        _ alert: WeatherAlert, now: Date, sensitivity: Sensitivity = .phone, heard: Set<String> = []
    ) -> Bool {
        guard inForce(alert, now: now), !sounds(alert, now: now, sensitivity: sensitivity, heard: heard) else {
            return false
        }
        return [" Warning", " Watch", " Emergency"].contains { alert.event.hasSuffix($0) }
    }

    // inForce reports whether an alert is real, not a cancel, not a statement that its event was canceled or
    // expired, and not past its end. The Weather Service sends expiration statements typed Alert or Update, so
    // the coded event action decides.
    static func inForce(_ alert: WeatherAlert, now: Date) -> Bool {
        guard alert.status == "Actual", alert.messageType != "Cancel", !alert.ended else {
            return false
        }
        return alert.until.map { $0 > now } ?? true
    }

    // active returns the alerts that sound at the given sensitivity, most dangerous first, leaving out any alert
    // that another alert in the list updates or cancels, so a canceled warning clears at once and an updated one
    // shows only its latest message. An alert in force whose chain is in heard stays active, so a warning that
    // already sounded stays red on updates that lose the phone flag.
    public static func active(
        _ alerts: [WeatherAlert], now: Date, sensitivity: Sensitivity = .phone, heard: Set<String> = []
    ) -> [WeatherAlert] {
        let replaced = replaced(alerts, now: now)
        return ranked(
            alerts.filter {
                !replaced.contains($0.id) && sounds($0, now: now, sensitivity: sensitivity, heard: heard)
            })
    }

    // notices returns the notable alerts, most dangerous first, leaving out any alert that another alert in the
    // list updates or cancels, so a canceled watch drops at once and an updated one shows only its latest message.
    // Pass the same heard as to active, so an alert never shows in both.
    public static func notices(
        _ alerts: [WeatherAlert], now: Date, sensitivity: Sensitivity = .phone, heard: Set<String> = []
    ) -> [WeatherAlert] {
        let replaced = replaced(alerts, now: now)
        return ranked(
            alerts.filter {
                !replaced.contains($0.id) && notable($0, now: now, sensitivity: sensitivity, heard: heard)
            })
    }

    // replaced returns the identifiers of alerts that a later update or cancel, already sent by now, replaces.
    static func replaced(_ alerts: [WeatherAlert], now: Date) -> Set<String> {
        Set(alerts.filter { $0.sent <= now }.flatMap(\.references))
    }

    // danger ranks an alert for display, lower first. Life-safety events and tornado events rank 0, other alerts
    // at the phone level rank 1, and the rest rank 2.
    static func danger(_ alert: WeatherAlert) -> Int {
        if lifeSafety.contains(alert.event) || alert.event.hasPrefix("Tornado ") {
            return 0
        }
        return phoneLevel(alert) ? 1 : 2
    }

    // ranked sorts alerts by danger, then newest first, so a tornado warning never hides behind a newer flood
    // update.
    static func ranked(_ alerts: [WeatherAlert]) -> [WeatherAlert] {
        alerts.sorted { a, b in
            danger(a) != danger(b) ? danger(a) < danger(b) : a.sent > b.sent
        }
    }

    // ring returns the active alerts that have not sounded yet, most dangerous first, and the names heard after
    // them. An alert already sounded when its identifier, any identifier it references, any expired identifier it
    // names, or its chain is in heard, so every later message about a warning stays quiet, whatever its type. A
    // warning that sounded rings again once when an update raises its damage threat to catastrophic, since phones
    // alert again for a tornado emergency or a flash flood emergency.
    public static func ring(_ active: [WeatherAlert], heard: Set<String>) -> (ring: [WeatherAlert], heard: Set<String>)
    {
        var heard = heard
        var rung: Set<String> = []
        for alert in active.sorted(by: { $0.sent < $1.sent }) {
            let keys = alert.keys
            let marks = Set(keys.map(catastrophicMark))
            if heard.isDisjoint(with: keys) || (alert.catastrophic && heard.isDisjoint(with: marks)) {
                rung.insert(alert.id)
            }
            heard.formUnion(keys)
            if alert.catastrophic {
                heard.formUnion(marks)
            }
        }
        return (ranked(active.filter { rung.contains($0.id) }), heard)
    }

    // catastrophicMark is the name ring puts in heard once a warning sounded at a catastrophic damage threat, so
    // the rise rings only once. It holds a space, which no identifier or chain does.
    static func catastrophicMark(_ key: String) -> String {
        "CATASTROPHIC " + key
    }

    // tier returns how loudly a national headline interrupts. A story first has to reach red's outlet count
    // within the window. It reaches the top tier when it also reaches the top count and one of its titles
    // carries a top tier phrase.
    public static func tier(_ headline: Headline, rules: NationalRules) -> Tier {
        let outlets = outletsWithin(headline, window: rules.window)
        guard outlets >= rules.redOutlets else {
            return .none
        }
        if outlets >= rules.topOutlets, topPhrase(headline, rules: rules) != nil {
            return .top
        }
        return .red
    }

    // national returns the fresh headlines that reach the red tier or higher, loudest first, each with its tier. A
    // headline stays an emergency for the rules' span after its first report.
    public static func national(_ headlines: [Headline], rules: NationalRules, now: Date) -> [(Headline, Tier)] {
        let picked = headlines.compactMap { headline -> (Headline, Tier)? in
            guard let first = headline.first, now.timeIntervalSince(first) < rules.span else {
                return nil
            }
            let tier = tier(headline, rules: rules)
            return tier == .none ? nil : (headline, tier)
        }
        return picked.enumerated().sorted { a, b in
            a.element.1 != b.element.1 ? a.element.1 > b.element.1 : a.offset < b.offset
        }.map(\.element)
    }

    // outletsWithin counts the distinct outlets that carried a headline within the window after its first
    // story. Stories without a publish date do not count, since their timing is unknown.
    public static func outletsWithin(_ headline: Headline, window: TimeInterval) -> Int {
        guard let first = headline.first else {
            return 0
        }
        let early = headline.stories.filter { story in
            story.published.map { $0.timeIntervalSince(first) <= window } ?? false
        }
        return Set(early.map(\.outlet)).count
    }

    // topPhrase returns the first top tier phrase found in any of a headline's titles, or nil.
    public static func topPhrase(_ headline: Headline, rules: NationalRules) -> String? {
        let titles = headline.stories.map { fold($0.title) }
        return rules.phrases.first { phrase in titles.contains { $0.contains(phrase) } }
    }

    // fold lowercases a title, drops apostrophes, and turns every run of other punctuation into one space, so
    // "U.S. declares war" and "U.S. Declares War" read alike.
    static func fold(_ title: String) -> String {
        let lowered = title.lowercased().replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "\u{2019}", with: "")
        let words = lowered.split { !$0.isLetter && !$0.isNumber }
        return " " + words.joined(separator: " ") + " "
    }
}

// NationalRules decides when a national story counts as an emergency. The outlet counts are starting values
// that still need measuring on live feeds before the national tier is offered in settings.
public struct NationalRules: Codable, Sendable, Equatable {
    // redOutlets is how many separate outlets must carry a story within the window to turn the ticker red.
    public var redOutlets = 12
    // topOutlets is how many separate outlets must carry a top tier story within the window to sound.
    public var topOutlets = 12
    // window is how soon after a story's first report the outlets must carry it.
    public var window: TimeInterval = 3600
    // span is how long after its first report a story stays an emergency.
    public var span: TimeInterval = 3 * 3600
    // phrases mark a story as top tier. Each is folded as Emergency.fold folds titles, with a space on each end
    // so it matches whole words.
    public var phrases = NationalRules.defaultPhrases

    // defaultPhrases are the top tier phrases: wars, declared national emergencies, martial law, and nuclear
    // attacks.
    public static let defaultPhrases = [
        " declares war ", " declared war ", " declaration of war ", " national emergency ", " martial law ",
        " nuclear attack ", " nuclear strike ", " nuclear detonation ", " nuclear explosion ",
    ]

    // init builds the starting rules.
    public init() {}
}
