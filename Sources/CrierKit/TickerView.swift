import AppKit
import SwiftUI

// TickerView scrolls the ticker entries right to left in an endless loop. Hovering holds it still and clicking
// a headline opens it. A red dot marks a major story and a small tag names the follow a headline came from.
//
// The row is laid out once by SwiftUI and slid by a Core Animation layer animation, so the scroll runs in the
// window server and costs the app almost nothing. It tracks the mouse and takes the first click whether or not
// its app is active, so it works in a panel that never activates.
//
// Tickers that share a clock scroll as one: each shows the row at its offset from its display's left edge, so a
// ticker split around Fuginaut's clock reads as one row passing behind it, and hovering either side holds both.
public struct TickerView: View {
    // entries are the headlines to scroll.
    let entries: [Entry]
    // speed is how fast headlines scroll, in points per second.
    let speed: Double
    // paused holds the ticker still.
    let paused: Bool
    // font draws the headlines.
    let font: Font
    // color draws the headlines, or nil for the primary label color.
    let color: Color?
    // offset is the ticker's left edge measured from its display's left edge, which places it along a shared row.
    let offset: CGFloat
    // clock is the scroll this ticker shares with others, or nil for a ticker that scrolls on its own.
    let clock: MarqueeClock?
    // onOpen runs when a headline is clicked. When nil, the headline's link opens in the browser.
    let onOpen: ((Entry) -> Void)?

    // openURL opens links when there is no onOpen.
    @Environment(\.openURL) private var openURL

    // init builds a ticker.
    public init(
        entries: [Entry], speed: Double = 40, paused: Bool = false, font: Font = .system(size: 13),
        color: Color? = nil, offset: CGFloat = 0, clock: MarqueeClock? = nil, onOpen: ((Entry) -> Void)? = nil
    ) {
        self.entries = entries
        self.speed = speed
        self.paused = paused
        self.font = font
        self.color = color
        self.offset = offset
        self.clock = clock
        self.onOpen = onOpen
    }

    // body draws the marquee, or a placeholder until the first headlines arrive.
    public var body: some View {
        if entries.isEmpty {
            Text("Reading the news…")
                .font(font)
                .foregroundStyle(color.map { AnyShapeStyle($0.opacity(0.6)) } ?? AnyShapeStyle(.secondary))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            MarqueeRepresentable(
                entries: entries, speed: speed, paused: paused, font: font, color: color, offset: offset, clock: clock
            ) { entry in
                if let onOpen {
                    onOpen(entry)
                } else {
                    openURL(entry.headline.lead.link)
                }
            }
        }
    }
}

// MarqueeRepresentable puts a MarqueeView in a SwiftUI hierarchy.
struct MarqueeRepresentable: NSViewRepresentable {
    // entries are the headlines to scroll.
    let entries: [Entry]
    // speed is how fast headlines scroll, in points per second.
    let speed: Double
    // paused holds the ticker still.
    let paused: Bool
    // font draws the headlines.
    let font: Font
    // color draws the headlines, or nil for the primary label color.
    let color: Color?
    // offset is the marquee's left edge measured from its display's left edge.
    let offset: CGFloat
    // clock is the shared scroll, or nil to use the marquee's own.
    let clock: MarqueeClock?
    // open runs when a headline is clicked.
    let open: (Entry) -> Void

    // Coordinator holds the clock a marquee uses when it shares none.
    @MainActor
    final class Coordinator {
        // clock is the marquee's own scroll.
        let clock = MarqueeClock()
    }

    // makeCoordinator builds the marquee's own clock.
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    // makeNSView builds the marquee.
    func makeNSView(context: Context) -> MarqueeView {
        MarqueeView()
    }

    // updateNSView hands the marquee the latest entries and settings, and the color scheme its host draws in,
    // since SwiftUI's environment stops at the marquee's own hosting view.
    func updateNSView(_ view: MarqueeView, context: Context) {
        view.open = open
        view.appearance = NSAppearance(named: context.environment.colorScheme == .dark ? .darkAqua : .aqua)
        let clock = clock ?? context.coordinator.clock
        view.update(entries: entries, font: font, color: color, offset: offset, clock: clock)
        clock.configure(speed: speed, paused: paused)
    }
}

// Spans records where each headline sits along one copy of the row.
@MainActor
final class Spans {
    // frames maps an entry's id to its frame in the row.
    var frames: [String: CGRect] = [:]
}

// MarqueeView draws copies of the row side by side and slides them left one copy's width at a time, so the next
// copy takes the first's place the moment it scrolls out of sight. Where the row sits comes from the clock.
final class MarqueeView: NSView {
    // open runs when a headline is clicked.
    var open: ((Entry) -> Void)?

    // strip holds the copies of the row and carries the scroll animation.
    private let strip = NSView()
    // host draws the row with SwiftUI.
    private let host = NSHostingView(
        rootView: MarqueeRow(entries: [], font: .body, color: nil, copies: 2, spans: Spans()))
    // fade softens both ends.
    private let fade = CAGradientLayer()
    // spans records where each headline sits.
    private let spans = Spans()
    // entries are the headlines on show.
    private var entries: [Entry] = []
    // font draws the headlines.
    private var font = Font.body
    // color draws the headlines, or nil for the primary label color.
    private var color: Color?
    // offset is the marquee's left edge measured from its display's left edge.
    private var offset: CGFloat = 0
    // clock is the scroll the marquee follows.
    private var clock: MarqueeClock?
    // copies is how many copies of the row the strip holds.
    private var copies = 2
    // width is the width of one copy of the row.
    private var width: CGFloat = 0
    // tracking is the area that reports the mouse.
    private var tracking: NSTrackingArea?

    // key names the scroll animation.
    private static let key = "marquee"
    // fadeWidth is the width of the soft edge on each side.
    private static let fadeWidth: CGFloat = 18

    // init builds the layers.
    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true
        strip.wantsLayer = true
        strip.addSubview(host)
        addSubview(strip)
        fade.startPoint = CGPoint(x: 0, y: 0.5)
        fade.endPoint = CGPoint(x: 1, y: 0.5)
        fade.colors = [NSColor.clear.cgColor, NSColor.black.cgColor, NSColor.black.cgColor, NSColor.clear.cgColor]
        layer?.mask = fade
    }

    // init is not supported, since the view is only built in code.
    required init?(coder: NSCoder) {
        nil
    }

    // update takes new entries, the marquee's place along the row, and the clock it follows.
    func update(entries: [Entry], font: Font, color: Color?, offset: CGFloat, clock: MarqueeClock) {
        attach(clock)
        let changed = entries != self.entries || font != self.font || color != self.color
        let moved = offset != self.offset
        self.entries = entries
        self.font = font
        self.color = color
        self.offset = offset
        if changed {
            spans.frames = [:]
            host.rootView = row()
            measure()
        }
        if changed || moved {
            run()
        }
    }

    // attach follows a clock, leaving any earlier one.
    private func attach(_ clock: MarqueeClock) {
        guard clock !== self.clock else {
            return
        }
        self.clock?.stop(self)
        self.clock = clock
        listen()
    }

    // listen restarts the scroll whenever the clock changes.
    private func listen() {
        clock?.listen(self) { [weak self] in
            self?.run()
        }
    }

    // viewDidMoveToWindow leaves the clock when the marquee leaves its window, so a panel taken away while the
    // mouse was over it does not hold the others, and follows it again on return.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            clock?.stop(self)
        } else {
            listen()
            run()
        }
    }

    // row builds the row's view with the current entries and copy count.
    private func row() -> MarqueeRow {
        MarqueeRow(entries: entries, font: font, color: color, copies: copies, spans: spans)
    }

    // layout centers the row vertically and fits the fade to the bounds.
    override func layout() {
        super.layout()
        if measure() {
            run()
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fade.frame = bounds
        let stop = bounds.width > 0 ? min(0.5, Self.fadeWidth / bounds.width) : 0
        fade.locations = [0, NSNumber(value: Double(stop)), NSNumber(value: Double(1 - stop)), 1]
        CATransaction.commit()
    }

    // measure sizes the row to fit, with enough copies to cover the marquee, and records one copy's width. It
    // reports whether the copy's width or count changed.
    @discardableResult
    private func measure() -> Bool {
        var size = host.fittingSize
        var one = size.width / CGFloat(copies)
        let need = Scroll.copies(width: one, panel: bounds.width)
        let grew = need != copies
        if grew {
            copies = need
            host.rootView = row()
            size = host.fittingSize
            one = size.width / CGFloat(copies)
        }
        let height = max(size.height, 1)
        let y = ((bounds.height - height) / 2).rounded()
        host.frame = CGRect(x: 0, y: 0, width: size.width, height: height)
        strip.frame = CGRect(x: strip.frame.minX, y: y, width: size.width, height: height)
        let changed = abs(one - width) > 0.5
        if changed {
            width = one
        }
        return changed || grew
    }

    // run starts the scroll in step with the clock, or holds the row where the clock stopped it.
    private func run() {
        guard let layer = strip.layer, let clock else {
            return
        }
        layer.removeAnimation(forKey: Self.key)
        let scroll = clock.scroll
        guard width > 0, scroll.moving else {
            strip.frame.origin.x = -scroll.phase(at: MarqueeClock.now, offset: offset, width: width)
            return
        }
        strip.frame.origin.x = 0
        let animation = CABasicAnimation(keyPath: "transform.translation.x")
        animation.fromValue = 0
        animation.toValue = -width
        animation.duration = Double(width) / scroll.speed
        animation.repeatCount = .infinity
        animation.beginTime = layer.convertTime(scroll.start, from: nil)
        animation.timeOffset = Double(scroll.phase(at: scroll.start, offset: offset, width: width)) / scroll.speed
        layer.add(animation, forKey: Self.key)
    }

    // updateTrackingAreas keeps one always-active tracking area over the whole view.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking {
            removeTrackingArea(tracking)
        }
        let area = NSTrackingArea(
            rect: .zero, options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect], owner: self, userInfo: nil
        )
        addTrackingArea(area)
        tracking = area
    }

    // mouseEntered holds every ticker on the clock.
    override func mouseEntered(with event: NSEvent) {
        clock?.hover(self, true)
    }

    // mouseExited lets them run again once the mouse is off all of them.
    override func mouseExited(with event: NSEvent) {
        clock?.hover(self, false)
    }

    // hitTest claims every point inside the view, so clicks come here rather than to the row.
    override func hitTest(_ point: NSPoint) -> NSView? {
        frame.contains(point) ? self : nil
    }

    // acceptsFirstMouse lets a click open a headline without first activating the app.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    // mouseDown is taken here, so the click is reported on mouseUp.
    override func mouseDown(with event: NSEvent) {}

    // mouseUp opens the headline under the pointer.
    override func mouseUp(with event: NSEvent) {
        guard width > 0, let clock else {
            return
        }
        let point = convert(event.locationInWindow, from: nil)
        let x = clock.scroll.position(of: point.x, at: MarqueeClock.now, offset: offset, width: width)
        let hit = entries.first { entry in
            guard let frame = spans.frames[entry.id] else {
                return false
            }
            return x >= frame.minX && x < frame.maxX
        }
        if let hit {
            open?(hit)
        }
    }
}

// MarqueeRow lays out copies of the entries side by side.
struct MarqueeRow: View {
    // entries are the headlines to lay out.
    let entries: [Entry]
    // font draws the headlines.
    let font: Font
    // color draws the headlines, or nil for the primary label color.
    let color: Color?
    // copies is how many copies of the entries to draw.
    let copies: Int
    // spans receives where each headline sits in the first copy.
    let spans: Spans

    // space names the row's coordinate space.
    nonisolated private static let space = "row"

    // body draws every copy.
    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<max(copies, 1), id: \.self) { index in
                copy(report: index == 0)
            }
        }
        .fixedSize()
        .foregroundStyle(color.map(AnyShapeStyle.init) ?? AnyShapeStyle(.primary))
        .coordinateSpace(.named(Self.space))
    }

    // copy draws one copy of the row, recording each item's frame when report is true.
    private func copy(report: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(entries) { entry in
                if report {
                    MarqueeItem(entry: entry, font: font)
                        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .named(Self.space)) }) { frame in
                            spans.frames[entry.id] = frame
                        }
                } else {
                    MarqueeItem(entry: entry, font: font)
                }
            }
        }
    }
}

// MarqueeItem draws one headline with its marks and the separator that follows it.
struct MarqueeItem: View {
    // entry is the headline to draw.
    let entry: Entry
    // font draws the headline.
    let font: Font

    // body draws the item.
    var body: some View {
        HStack(spacing: 5) {
            if entry.major {
                Circle()
                    .fill(Color.red)
                    .frame(width: 6, height: 6)
            }
            if let tag = entry.tag {
                Text(tag.uppercased())
                    .font(.system(size: 9, weight: .semibold))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.secondary.opacity(0.22)))
            }
            Text(entry.headline.lead.title)
                .font(font)
                .lineLimit(1)
            Text("·")
                .font(font)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 10)
        }
        .fixedSize()
    }
}
