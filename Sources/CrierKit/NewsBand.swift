import AppKit
import SwiftUI

// BandTheme colors a news band. A host with its own theme passes its colors. Without one, the band takes the
// light or dark default to match its surroundings.
public struct BandTheme: Sendable, Equatable {
    // background fills the band.
    public var background: Color
    // foreground draws text, rules, and page dots.
    public var foreground: Color
    // accent marks major stories and fills the rotation line.
    public var accent: Color
    // tile backs the bell beside the wordmark.
    public var tile: Color
    // bell colors the system bell drawn when the host passes no mark image, or nil for cream or ink to suit the
    // tile.
    public var bell: Color?

    // init builds a theme.
    public init(background: Color, foreground: Color, accent: Color, tile: Color, bell: Color? = nil) {
        self.background = background
        self.foreground = foreground
        self.accent = accent
        self.tile = tile
        self.bell = bell
    }

    // ink is the near black of the app icon's tile.
    public static let ink = Color(red: 32 / 255, green: 31 / 255, blue: 29 / 255)
    // paper is the warm cream of the bell.
    public static let paper = Color(red: 0.96, green: 0.93, blue: 0.86)
    // gold is a warm metallic gold, #C9A24B, for a host that wants the bell in color.
    public static let gold = Color(red: 201 / 255, green: 162 / 255, blue: 75 / 255)
    // dark sets cream type on ink.
    public static let dark = BandTheme(
        background: ink, foreground: paper, accent: Color(nsColor: .systemRed), tile: ink)
    // light sets ink type on cream.
    public static let light = BandTheme(
        background: paper, foreground: ink, accent: Color(nsColor: .systemRed), tile: ink)

    // isDark reports whether the background is dark, so controls drawn by the system pick matching colors.
    public var isDark: Bool {
        guard let color = NSColor(background).usingColorSpace(.sRGB) else {
            return false
        }
        let luminance = 0.2126 * color.redComponent + 0.7152 * color.greenComponent + 0.0722 * color.blueComponent
        return luminance < 0.5
    }
}

// NewsBand shows the top stories as pinned columns that rotate on a timer, a thin line filling toward the
// next rotation, and the ticker scrolling the rest of the news along the bottom. It always spans the full
// width it is given. It pins as many stories as fit, from three to five, and when fewer stories than that
// exist, the ones there widen to fill the row. Hovering the pinned stories holds the rotation, a page dot jumps to its
// page, and clicking a story opens it.
public struct NewsBand: View {
    // entries are the ticker's items, most important first, as News keeps them.
    let entries: [Entry]
    // theme colors the band, or nil for the default that matches the color scheme.
    let theme: BandTheme?
    // mark is the bell beside the wordmark, or nil for the system bell symbol.
    let mark: Image?
    // rotation is how long each page of pinned stories stays up.
    let rotation: Duration
    // speed is how fast the ticker scrolls, in points per second.
    let speed: Double
    // onOpen runs when a story is clicked. When nil, the story's link opens in the browser.
    let onOpen: ((Entry) -> Void)?

    // scheme picks the default theme.
    @Environment(\.colorScheme) private var scheme
    // openURL opens links when there is no onOpen.
    @Environment(\.openURL) private var openURL
    // width is the band's measured width, which sets how many stories are pinned.
    @State private var width: CGFloat = 0
    // page counts rotations. The page on show is this modulo the page count.
    @State private var page = 0
    // spent is how long the current page has been up before the running stretch, kept across holds.
    @State private var spent = Duration.zero
    // hovered holds the rotation while the mouse is over the pinned stories.
    @State private var hovered = false

    // minColumns and maxColumns bound how many stories are pinned at once.
    public static let minColumns = 3
    public static let maxColumns = 5
    // columnWidth is the narrowest a pinned story reads well at.
    static let columnWidth: CGFloat = 340
    // brandWidth is the width of the bell, wordmark, and page dots.
    static let brandWidth: CGFloat = 96
    // pinnedStories is about how many top stories take turns in the pinned columns. The rest scroll in the
    // ticker.
    static let pinnedStories = 12
    // tickerHeight is the height of the ticker row.
    static let tickerHeight: CGFloat = 30

    // init builds a band.
    public init(
        entries: [Entry], theme: BandTheme? = nil, mark: Image? = nil, rotation: Duration = .seconds(30),
        speed: Double = 40, onOpen: ((Entry) -> Void)? = nil
    ) {
        self.entries = entries
        self.theme = theme
        self.mark = mark
        self.rotation = rotation
        self.speed = speed
        self.onOpen = onOpen
    }

    // columns returns how many stories fit side by side in a band of the given width, from three to five.
    static func columns(for width: CGFloat) -> Int {
        let fit = Int(max(0, width - brandWidth) / columnWidth)
        return min(max(fit, minColumns), maxColumns)
    }

    // layout splits the entries into pages of pinned general stories, whole pages only, and the rest for the
    // ticker. Followed stories always go to the ticker, one after every three general stories, so they never
    // bunch up at its start.
    static func layout(_ entries: [Entry], columns: Int) -> (pages: [[Entry]], rest: [Entry]) {
        let general = entries.filter { $0.tag == nil }
        let most = max(1, pinnedStories / columns) * columns
        var count = min(general.count, most)
        if count >= columns {
            count -= count % columns
        }
        let pinned = Array(general.prefix(count))
        let pages = stride(from: 0, to: pinned.count, by: columns).map {
            Array(pinned[$0..<min($0 + columns, pinned.count)])
        }
        var rest = Array(general.dropFirst(count))
        var slot = 1
        for followed in entries where followed.tag != nil {
            rest.insert(followed, at: min(slot, rest.count))
            slot += 4
        }
        return (pages, rest)
    }

    // body draws the pinned stories over the rotation line and the ticker.
    public var body: some View {
        let theme = theme ?? (scheme == .dark ? .dark : .light)
        let columns = Self.columns(for: width)
        let layout = Self.layout(entries, columns: columns)
        let pages = layout.pages
        let index = pages.isEmpty ? 0 : page % pages.count
        let running = pages.count > 1 && !hovered
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                brand(theme: theme, pages: pages.count, index: index)
                if pages.isEmpty {
                    Text("Reading the news…")
                        .font(.system(size: 16, weight: .semibold, design: .serif))
                        .foregroundStyle(theme.foreground.opacity(0.6))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(pages[index]) { entry in
                            rule(theme)
                            card(entry, theme: theme)
                        }
                    }
                    .id(index)
                    .transition(.opacity)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .onHover { hovered = $0 }
            ProgressLine(
                cycle: page, running: running, from: fraction, duration: remaining,
                track: theme.foreground.opacity(0.08), fill: theme.accent.opacity(0.75)
            )
            .frame(height: 2)
            TickerView(
                entries: layout.rest, speed: speed, font: .system(size: 13), color: theme.foreground, onOpen: onOpen
            )
            .padding(.horizontal, 8)
            .frame(height: Self.tickerHeight)
        }
        .background(theme.background)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(theme.foreground.opacity(0.12)))
        .environment(\.colorScheme, theme.isDark ? .dark : .light)
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { width = $0 }
        .task(id: Rotation(page: page, pages: pages.count, running: running)) {
            guard running else {
                return
            }
            let start = ContinuousClock.now
            do {
                try await Task.sleep(for: rotation - spent)
            } catch {
                spent += ContinuousClock.now - start
                return
            }
            spent = .zero
            withAnimation(.easeInOut(duration: 0.35)) {
                page += 1
            }
        }
    }

    // fraction is how much of the current page's time has passed.
    private var fraction: Double {
        min(1, spent / rotation)
    }

    // remaining is how many seconds the current page has left.
    private var remaining: Double {
        let left = rotation - spent
        return Double(left.components.seconds) + Double(left.components.attoseconds) / 1e18
    }

    // brand draws the bell on its tile, the serif wordmark, and one dot per page.
    private func brand(theme: BandTheme, pages: Int, index: Int) -> some View {
        VStack(spacing: 6) {
            Group {
                if let mark {
                    mark.resizable().interpolation(.high).scaledToFit()
                } else {
                    Image(systemName: "bell.fill").resizable().scaledToFit().foregroundStyle(Self.bellColor(theme))
                }
            }
            .frame(height: 30)
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 9).fill(theme.tile))
            Text("CRIER")
                .font(.system(size: 13, weight: .semibold, design: .serif))
                .tracking(3)
                .foregroundStyle(theme.foreground)
            HStack(spacing: 4) {
                ForEach(0..<max(pages, 1), id: \.self) { dot in
                    Button {
                        spent = .zero
                        withAnimation(.easeInOut(duration: 0.35)) {
                            page = page - index + dot
                        }
                    } label: {
                        Circle()
                            .fill(theme.foreground.opacity(dot == index ? 0.9 : 0.25))
                            .frame(width: 5, height: 5)
                            .padding(2)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(pages < 2)
                }
            }
        }
        .frame(width: Self.brandWidth)
        .padding(.vertical, 12)
    }

    // bellColor returns the color the fallback bell takes: the theme's bell color, else cream or ink to suit the
    // tile.
    static func bellColor(_ theme: BandTheme) -> Color {
        theme.bell ?? (theme.tile == BandTheme.paper ? BandTheme.ink : BandTheme.paper)
    }

    // rule draws the thin line between columns.
    private func rule(_ theme: BandTheme) -> some View {
        Rectangle()
            .fill(theme.foreground.opacity(0.12))
            .frame(width: 1)
            .padding(.vertical, 12)
    }

    // card draws one pinned story as a button that opens it.
    private func card(_ entry: Entry, theme: BandTheme) -> some View {
        Button {
            if let onOpen {
                onOpen(entry)
            } else {
                openURL(entry.headline.lead.link)
            }
        } label: {
            BandCard(entry: entry, theme: theme)
        }
        .buttonStyle(.plain)
    }
}

// Rotation keys the rotation timer, so it restarts when the page, the page count, or the hold changes.
struct Rotation: Equatable {
    // page counts rotations.
    let page: Int
    // pages is how many pages there are.
    let pages: Int
    // running reports whether the rotation runs.
    let running: Bool
}

// BandCard draws one pinned story: its outlet with a major mark, its title in two serif lines, and how many
// outlets carry it and how old it is.
struct BandCard: View {
    // entry is the story to draw.
    let entry: Entry
    // theme colors the card.
    let theme: BandTheme

    // hovered lights the card under the mouse.
    @State private var hovered = false

    // body draws the card.
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if entry.major {
                    Circle().fill(theme.accent).frame(width: 7, height: 7)
                    Text("MAJOR")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(theme.accent)
                }
                Text(entry.headline.lead.outlet.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(theme.foreground.opacity(0.6))
                    .lineLimit(1)
            }
            Text(entry.headline.lead.title)
                .font(.system(size: 16, weight: .semibold, design: .serif))
                .foregroundStyle(theme.foreground)
                .lineLimit(2, reservesSpace: true)
                .multilineTextAlignment(.leading)
            Text(Self.detail(entry.headline))
                .font(.system(size: 11))
                .foregroundStyle(theme.foreground.opacity(0.6))
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(theme.foreground.opacity(hovered ? 0.05 : 0))
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .help(entry.headline.lead.title)
    }

    // detail says how many outlets carry the story and when the newest report went out.
    static func detail(_ headline: Headline) -> String {
        let count = headline.outlets.count
        var parts = [count == 1 ? "1 outlet" : "\(count) outlets"]
        if let latest = headline.latest {
            parts.append(latest.formatted(.relative(presentation: .named)))
        }
        return parts.joined(separator: " · ")
    }
}

// ProgressLine draws the thin line that fills toward the next rotation. The fill runs as a Core Animation
// layer animation, so it costs the app nothing between rotations. It starts over when the cycle changes,
// stops where it is when held, and picks up from the given fraction when it runs again.
struct ProgressLine: NSViewRepresentable {
    // cycle changes with every rotation.
    let cycle: Int
    // running fills the line. When false, the line holds still.
    let running: Bool
    // from is the fraction already filled when the line starts running.
    let from: Double
    // duration is how many seconds the rest of the fill takes.
    let duration: Double
    // track is the unfilled line's color.
    let track: Color
    // fill is the filled part's color.
    let fill: Color

    // makeNSView builds the line.
    func makeNSView(context: Context) -> ProgressLineView {
        ProgressLineView()
    }

    // updateNSView recolors the line and starts, holds, or restarts the fill.
    func updateNSView(_ view: ProgressLineView, context: Context) {
        view.update(
            cycle: cycle, running: running, from: from, duration: duration, track: NSColor(track),
            fill: NSColor(fill))
    }
}

// ProgressLineView is the layer-backed view behind ProgressLine.
final class ProgressLineView: NSView {
    // bar is the filled part, scaled from the left edge.
    private let bar = CALayer()
    // cycle is the cycle the fill belongs to.
    private var cycle: Int?
    // running reports whether the fill is animating.
    private var running = false

    // key names the fill animation.
    private static let key = "fill"

    // init builds the layers.
    init() {
        super.init(frame: .zero)
        wantsLayer = true
        bar.anchorPoint = CGPoint(x: 0, y: 0.5)
        bar.transform = CATransform3DMakeScale(0, 1, 1)
        layer?.addSublayer(bar)
    }

    // init is not supported, since the view is only built in code.
    required init?(coder: NSCoder) {
        nil
    }

    // layout stretches the bar across the view.
    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        bar.bounds = CGRect(origin: .zero, size: bounds.size)
        bar.position = CGPoint(x: 0, y: bounds.midY)
        CATransaction.commit()
    }

    // update recolors the line, and starts, holds, or restarts the fill when the cycle or the hold changes.
    func update(cycle: Int, running: Bool, from: Double, duration: Double, track: NSColor, fill: NSColor) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        layer?.backgroundColor = track.cgColor
        bar.backgroundColor = fill.cgColor
        let newCycle = cycle != self.cycle
        guard newCycle || running != self.running else {
            return
        }
        self.cycle = cycle
        self.running = running
        let current = (bar.presentation()?.value(forKeyPath: "transform.scale.x") as? CGFloat) ?? 0
        bar.removeAnimation(forKey: Self.key)
        guard running else {
            bar.transform = CATransform3DMakeScale(newCycle ? 0 : current, 1, 1)
            return
        }
        let start = newCycle ? 0 : CGFloat(from)
        bar.transform = CATransform3DMakeScale(1, 1, 1)
        let animation = CABasicAnimation(keyPath: "transform.scale.x")
        animation.fromValue = start
        animation.toValue = 1
        animation.duration = max(0.01, duration)
        bar.add(animation, forKey: Self.key)
    }
}
