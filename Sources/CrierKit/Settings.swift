import AppKit
import SwiftUI

// Place is where the ticker sits.
public enum Place: String, Codable, CaseIterable, Sendable {
    // menuBar draws the ticker in the menu bar's empty middle, like a clock app.
    case menuBar
    // belowMenuBar draws a full width strip just under the menu bar.
    case belowMenuBar

    // title names the place in settings.
    public var title: String {
        switch self {
        case .menuBar: "In the menu bar"
        case .belowMenuBar: "Strip below the menu bar"
        }
    }
}

// Position is where the menu bar ticker sits along the bar.
public enum Position: String, Codable, CaseIterable, Sendable {
    // center sits in the middle of the bar.
    case center
    // leftOfCenter ends just left of the middle, which leaves the middle to a clock.
    case leftOfCenter
    // rightOfCenter starts just right of the middle.
    case rightOfCenter

    // title names the position in settings.
    public var title: String {
        switch self {
        case .center: "Center"
        case .leftOfCenter: "Left of center"
        case .rightOfCenter: "Right of center"
        }
    }
}

// StoredColor is a color kept in settings as sRGB components.
public struct StoredColor: Codable, Sendable, Hashable {
    // red, green, blue, and alpha run from 0 to 1.
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    // init builds a color from components.
    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    // init converts a SwiftUI color, falling back to black when it has no sRGB form.
    public init(_ color: Color) {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .black
        self.init(
            red: Double(ns.redComponent), green: Double(ns.greenComponent), blue: Double(ns.blueComponent),
            alpha: Double(ns.alphaComponent))
    }

    // color is the stored color for SwiftUI.
    public var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}

// Look picks the colors of the news band and Crier's window.
public enum Look: String, Codable, CaseIterable, Sendable {
    // automatic follows light and dark mode.
    case automatic
    // ink sets cream type on near black.
    case ink
    // paper sets near black type on cream.
    case paper
    // custom uses the reader's own colors.
    case custom

    // title names the look in settings.
    public var title: String {
        switch self {
        case .automatic: "Match light or dark mode"
        case .ink: "Ink"
        case .paper: "Paper"
        case .custom: "My colors"
        }
    }
}

// CustomLook holds the reader's own band colors.
public struct CustomLook: Codable, Sendable, Hashable {
    // background fills the band.
    public var background = StoredColor(red: 0.11, green: 0.16, blue: 0.24)
    // text draws headlines and rules.
    public var text = StoredColor(red: 0.95, green: 0.95, blue: 0.93)
    // accent marks major stories and fills the rotation line.
    public var accent = StoredColor(red: 1, green: 0.27, blue: 0.23)

    // init builds the starting custom colors.
    public init() {}
}

// CustomFeed is an RSS or Atom feed the reader adds, such as one curated in another app.
public struct CustomFeed: Codable, Sendable, Hashable, Identifiable {
    // name labels the feed's stories as their outlet.
    public var name: String
    // url is the feed address.
    public var url: String

    // init builds a custom feed.
    public init(name: String, url: String) {
        self.name = name
        self.url = url
    }

    // id is the feed address.
    public var id: String {
        url
    }

    // source is the feed as a source, or nil when the address is not a web address.
    public var source: Source? {
        guard let url = URL(string: url.trimmingCharacters(in: .whitespaces)), url.scheme?.hasPrefix("http") == true
        else {
            return nil
        }
        let label = name.trimmingCharacters(in: .whitespaces)
        return Source(
            id: "custom:\(url.absoluteString)", outlet: label.isEmpty ? url.host() : label, url: url, topic: .top)
    }
}

// AlertRules decides when a story is big enough to interrupt.
public struct AlertRules: Codable, Sendable, Equatable {
    // enabled turns major story alerts on.
    public var enabled = true
    // minOutlets is how many separate outlets must carry a story before it counts as major.
    public var minOutlets = 6
    // dailyCap is the most alerts sent in one calendar day.
    public var dailyCap = 3
    // quietStart is the hour, from 0 to 23, when quiet hours begin. Equal start and end means no quiet hours.
    public var quietStart = 22
    // quietEnd is the hour, from 0 to 23, when quiet hours end.
    public var quietEnd = 7
    // maxAgeHours is how old a story may be and still alert.
    public var maxAgeHours = 6.0

    // init builds the default rules.
    public init() {}
}

// EmergencyMode picks which emergencies interrupt.
public enum EmergencyMode: String, Codable, CaseIterable, Sendable {
    // off never interrupts for an emergency.
    case off
    // local interrupts for life-safety warnings that cover the reader's area.
    case local
    // localAndNational also interrupts for national stories far bigger than major.
    case localAndNational

    // title names the mode in settings.
    public var title: String {
        switch self {
        case .off: "Off"
        case .local: "Local warnings"
        case .localAndNational: "Local warnings and national breaking news"
        }
    }
}

// EmergencyRules holds the emergency mode choices.
public struct EmergencyRules: Codable, Sendable, Equatable {
    // mode picks which emergencies interrupt.
    public var mode = EmergencyMode.local
    // zip is the ZIP code that sets the reader's area. Empty means the Mac's location.
    public var zip = ""
    // sound plays the emergency sound for top tier emergencies.
    public var sound = true
    // flashing pulses the ticker for top tier emergencies.
    public var flashing = true
    // national decides when a national story counts as an emergency.
    public var national = NationalRules()

    // init builds the default emergency choices.
    public init() {}

    // init decodes the stored fields and defaults the missing ones.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mode = (try? c.decodeIfPresent(EmergencyMode.self, forKey: .mode)) ?? mode
        zip = try c.decodeIfPresent(String.self, forKey: .zip) ?? zip
        sound = try c.decodeIfPresent(Bool.self, forKey: .sound) ?? sound
        flashing = try c.decodeIfPresent(Bool.self, forKey: .flashing) ?? flashing
        national = (try? c.decodeIfPresent(NationalRules.self, forKey: .national)) ?? national
    }
}

// Settings holds every choice the reader makes.
public struct Settings: Codable, Sendable, Equatable {
    // tickerOn shows the ticker.
    public var tickerOn = true
    // place is where the ticker sits.
    public var place = Place.menuBar
    // width is the ticker's width in points when it sits in the menu bar.
    public var width = 560.0
    // offset nudges the menu bar ticker right of center, or left when negative.
    public var offset = 0.0
    // position is where the menu bar ticker sits along the bar.
    public var position = Position.center
    // fill stretches the menu bar ticker across the open bar on its position's side instead of using width. It is
    // on by default, since a fixed width reads as a narrow slot on a wide display.
    public var fill = true
    // menuRoom is how much of the bar's left end is kept for app menus when Crier cannot read where they end.
    public var menuRoom = 900.0
    // speed is how fast headlines scroll, in points per second.
    public var speed = 40.0
    // allDisplays shows the ticker on every display instead of only the main one.
    public var allDisplays = false
    // interest is how much of each topic the reader wants. A topic missing from it counts as normal.
    public var interest = Interest.defaults
    // follows are the teams and subjects kept in the ticker.
    public var follows = Follow.defaults
    // feeds are the reader's own feeds.
    public var feeds: [CustomFeed] = []
    // refreshMinutes is how often the feeds are read.
    public var refreshMinutes = 5.0
    // disabledSources holds the ids of catalog feeds the reader turned off.
    public var disabledSources: Set<String> = []
    // tickerColor draws the ticker's headlines, or nil to match the menu bar's own text.
    public var tickerColor: StoredColor?
    // look picks the news band's colors.
    public var look = Look.automatic
    // customLook holds the colors used when look is custom.
    public var customLook = CustomLook()
    // rotationSeconds is how long each page of pinned stories stays up in the news band.
    public var rotationSeconds = 30.0
    // alerts are the major story alert rules.
    public var alerts = AlertRules()
    // emergency holds the emergency mode choices.
    public var emergency = EmergencyRules()

    // init builds the default settings.
    public init() {}

    // sources returns every feed these settings read.
    public var sources: [Source] {
        Source.sources(for: interest, follows: follows).filter { !disabledSources.contains($0.id) }
            + feeds.compactMap(\.source)
    }

    // level returns how much of a topic the reader wants.
    public func level(_ topic: Topic) -> Interest {
        interest[topic] ?? .normal
    }

    // theme returns the news band's colors, or nil to follow light and dark mode.
    public var theme: BandTheme? {
        switch look {
        case .automatic:
            return nil
        case .ink:
            return .dark
        case .paper:
            return .light
        case .custom:
            return BandTheme(
                background: customLook.background.color, foreground: customLook.text.color,
                accent: customLook.accent.color, tile: BandTheme.ink)
        }
    }
}

// Settings decodes field by field, so settings saved by an older version keep every choice they hold and
// take the default for anything new.
extension Settings {
    // CodingKeys names the stored fields.
    private enum CodingKeys: String, CodingKey {
        case tickerOn, place, width, offset, speed, allDisplays, interest, follows, feeds, refreshMinutes, alerts
        case disabledSources, tickerColor, look, customLook, rotationSeconds, position, fill, menuRoom
        case emergency
    }

    // init decodes the stored fields and defaults the missing ones.
    public init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tickerOn = try c.decodeIfPresent(Bool.self, forKey: .tickerOn) ?? tickerOn
        place = (try? c.decodeIfPresent(Place.self, forKey: .place)) ?? place
        width = try c.decodeIfPresent(Double.self, forKey: .width) ?? width
        offset = try c.decodeIfPresent(Double.self, forKey: .offset) ?? offset
        speed = try c.decodeIfPresent(Double.self, forKey: .speed) ?? speed
        allDisplays = try c.decodeIfPresent(Bool.self, forKey: .allDisplays) ?? allDisplays
        if let stored = try c.decodeIfPresent([String: String].self, forKey: .interest) {
            for (name, level) in stored {
                if let topic = Topic(rawValue: name), let level = Interest(rawValue: level) {
                    interest[topic] = level
                }
            }
        }
        follows = try c.decodeIfPresent([Follow].self, forKey: .follows) ?? follows
        feeds = try c.decodeIfPresent([CustomFeed].self, forKey: .feeds) ?? feeds
        refreshMinutes = try c.decodeIfPresent(Double.self, forKey: .refreshMinutes) ?? refreshMinutes
        alerts = try c.decodeIfPresent(AlertRules.self, forKey: .alerts) ?? alerts
        disabledSources = try c.decodeIfPresent(Set<String>.self, forKey: .disabledSources) ?? disabledSources
        tickerColor = try c.decodeIfPresent(StoredColor.self, forKey: .tickerColor)
        look = (try? c.decodeIfPresent(Look.self, forKey: .look)) ?? look
        customLook = try c.decodeIfPresent(CustomLook.self, forKey: .customLook) ?? customLook
        rotationSeconds = try c.decodeIfPresent(Double.self, forKey: .rotationSeconds) ?? rotationSeconds
        position = (try? c.decodeIfPresent(Position.self, forKey: .position)) ?? position
        fill = try c.decodeIfPresent(Bool.self, forKey: .fill) ?? fill
        menuRoom = try c.decodeIfPresent(Double.self, forKey: .menuRoom) ?? menuRoom
        emergency = (try? c.decodeIfPresent(EmergencyRules.self, forKey: .emergency)) ?? emergency
    }

    // encode stores every field, with interest keyed by topic name.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(tickerOn, forKey: .tickerOn)
        try c.encode(place, forKey: .place)
        try c.encode(width, forKey: .width)
        try c.encode(offset, forKey: .offset)
        try c.encode(speed, forKey: .speed)
        try c.encode(allDisplays, forKey: .allDisplays)
        try c.encode(
            Dictionary(uniqueKeysWithValues: interest.map { ($0.key.rawValue, $0.value.rawValue) }), forKey: .interest)
        try c.encode(follows, forKey: .follows)
        try c.encode(feeds, forKey: .feeds)
        try c.encode(refreshMinutes, forKey: .refreshMinutes)
        try c.encode(alerts, forKey: .alerts)
        try c.encode(disabledSources.sorted(), forKey: .disabledSources)
        try c.encodeIfPresent(tickerColor, forKey: .tickerColor)
        try c.encode(look, forKey: .look)
        try c.encode(customLook, forKey: .customLook)
        try c.encode(rotationSeconds, forKey: .rotationSeconds)
        try c.encode(position, forKey: .position)
        try c.encode(fill, forKey: .fill)
        try c.encode(menuRoom, forKey: .menuRoom)
        try c.encode(emergency, forKey: .emergency)
    }
}
