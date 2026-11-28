import Foundation

// ThemeLook is the colors a Mac-wide theme draws Crier in. It sits over the reader's own ticker color and band
// look, and the reader's settings never change, so clearing it puts back exactly what the reader chose.
public struct ThemeLook: Equatable, Sendable {
    // notificationName is the distributed notification a theme switcher posts. Its object is a ThemeLookMessage.
    public static let notificationName = "com.dcadolph.crier.themeColor"
    // auto is the ticker word that keeps the menu bar's own text color.
    public static let auto = "auto"

    // ticker draws the ticker's headlines, or nil to match the menu bar's own text, for a theme color that would
    // wash out on the wallpaper under the menu bar.
    public var ticker: StoredColor?
    // background fills the news band.
    public var background: StoredColor
    // text draws the band's headlines and rules.
    public var text: StoredColor
    // accent marks the band's major stories and fills its rotation line.
    public var accent: StoredColor

    // init builds a theme look.
    public init(ticker: StoredColor?, background: StoredColor, text: StoredColor, accent: StoredColor) {
        self.ticker = ticker
        self.background = background
        self.text = text
        self.accent = accent
    }

    // message formats the look the way a theme switcher sends it, so it can be kept and read back later.
    public var message: String {
        [ticker.map(\.hex) ?? Self.auto, background.hex, text.hex, accent.hex].joined(separator: " ")
    }

    // applied returns the settings to draw: the reader's settings with the theme's ticker color and its band
    // colors as the custom look.
    public func applied(to settings: Settings) -> Settings {
        var drawn = settings
        drawn.tickerColor = ticker
        drawn.look = .custom
        drawn.customLook.background = background
        drawn.customLook.text = text
        drawn.customLook.accent = accent
        return drawn
    }
}

extension Settings {
    // drawn returns the settings to draw while a theme look is held, or the settings themselves without one.
    public func drawn(with theme: ThemeLook?) -> Settings {
        theme?.applied(to: self) ?? self
    }
}

// ThemeLookMessage is what a theme switcher's message asks for.
public enum ThemeLookMessage: Equatable, Sendable {
    // set draws Crier in a theme look.
    case set(ThemeLook)
    // clear puts back the reader's own colors.
    case clear
    // junk is a message that cannot be read, which changes nothing.
    case junk

    // init reads a message: empty clears, and four words set the look: the ticker color or "auto", then the
    // band's background, text, and accent, each #RRGGBB. Anything else is junk.
    public init(_ message: String) {
        let parts = message.split(whereSeparator: \.isWhitespace).map(String.init)
        if parts.isEmpty {
            self = .clear
            return
        }
        guard parts.count == 4 else {
            self = .junk
            return
        }
        let band = parts.dropFirst().compactMap(StoredColor.init(hex:))
        let ticker = parts[0] == ThemeLook.auto ? nil : StoredColor(hex: parts[0])
        guard band.count == 3, parts[0] == ThemeLook.auto || ticker != nil else {
            self = .junk
            return
        }
        self = .set(ThemeLook(ticker: ticker, background: band[0], text: band[1], accent: band[2]))
    }

    // updating returns the look to hold after this message arrives while current is held.
    public func updating(_ current: ThemeLook?) -> ThemeLook? {
        switch self {
        case .set(let look): look
        case .clear: nil
        case .junk: current
        }
    }
}

extension StoredColor {
    // init reads one opaque #RRGGBB color, or returns nil for any other form.
    public init?(hex: String) {
        guard hex.count == 7, hex.hasPrefix("#"), let value = UInt32(hex.dropFirst(), radix: 16) else {
            return nil
        }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255)
    }

    // hex is the color as #RRGGBB, alpha left out.
    public var hex: String {
        let byte = { (part: Double) in Int((min(max(part, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(red), byte(green), byte(blue))
    }
}
