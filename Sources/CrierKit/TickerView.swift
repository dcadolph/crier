import AppKit
import SwiftUI

// TickerView scrolls the ticker entries right to left in an endless loop. Hovering holds it still and clicking
// a headline opens it. A red dot marks a major story and a small tag names the follow a headline came from.
//
// The row is laid out once by SwiftUI and slid by a Core Animation layer animation, so the scroll runs in the
// window server and costs the app almost nothing. It tracks the mouse and takes the first click whether or not
// its app is active, so it works in a panel that never activates.
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
    // onOpen runs when a headline is clicked. When nil, the headline's link opens in the browser.
    let onOpen: ((Entry) -> Void)?

    // openURL opens links when there is no onOpen.
    @Environment(\.openURL) private var openURL

    // init builds a ticker.
    public init(
        entries: [Entry], speed: Double = 40, paused: Bool = false, font: Font = .system(size: 13),
        color: Color? = nil, onOpen: ((Entry) -> Void)? = nil
    ) {
        self.entries = entries
        self.speed = speed
        self.paused = paused
        self.font = font
        self.color = color
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
            MarqueeRepresentable(entries: entries, speed: speed, paused: paused, font: font, color: color) { entry in
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
    // open runs when a headline is clicked.
    let open: (Entry) -> Void

    // makeNSView builds the marquee.
    func makeNSView(context: Context) -> MarqueeView {
        MarqueeView()
    }

    // updateNSView hands the marquee the latest entries and settings, and the color scheme its host draws in,
    // since SwiftUI's environment stops at the marquee's own hosting view.
    func updateNSView(_ view: MarqueeView, context: Context) {
        view.open = open
        view.appearance = NSAppearance(named: context.environment.colorScheme == .dark ? .darkAqua : .aqua)
        view.update(entries: entries, font: font, color: color, speed: speed, paused: paused)
    }
}

// Spans records where each headline sits along one copy of the row.
@MainActor
final class Spans {
    // frames maps an entry's id to its frame in the row.
    var frames: [String: CGRect] = [:]
}

// MarqueeView draws the row twice, side by side, and slides both left, so the second copy takes the first's
// place the moment it scrolls out of sight.
final class MarqueeView: NSView {
    // open runs when a headline is clicked.
    var open: ((Entry) -> Void)?

    // strip holds the two copies of the row and carries the scroll animation.
    private let strip = NSView()
    // host draws the row with SwiftUI.
    private let host = NSHostingView(rootView: MarqueeRow(entries: [], font: .body, color: nil, spans: Spans()))
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
    // speed is how fast headlines scroll, in points per second.
    private var speed = 40.0
    // paused holds the ticker still at the caller's request.
    private var paused = false
    // hovered reports whether the mouse is over the ticker.
    private var hovered = false
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

    // held reports whether the ticker stands still.
    private var held: Bool {
        paused || hovered
    }

    // update takes new entries and settings, keeping the scroll's place.
    func update(entries: [Entry], font: Font, color: Color?, speed: Double, paused: Bool) {
        let phase = currentPhase()
        let changed = entries != self.entries || font != self.font || color != self.color
        self.entries = entries
        self.font = font
        self.color = color
        self.speed = speed
        self.paused = paused
        if changed {
            spans.frames = [:]
            host.rootView = MarqueeRow(entries: entries, font: font, color: color, spans: spans)
            measure()
        }
        run(from: phase)
    }

    // layout centers the row vertically and fits the fade to the bounds.
    override func layout() {
        super.layout()
        measure()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fade.frame = bounds
        let stop = bounds.width > 0 ? min(0.5, Self.fadeWidth / bounds.width) : 0
        fade.locations = [0, NSNumber(value: Double(stop)), NSNumber(value: Double(1 - stop)), 1]
        CATransaction.commit()
    }

    // measure sizes the row to fit and records one copy's width.
    private func measure() {
        let size = host.fittingSize
        let height = max(size.height, 1)
        let y = ((bounds.height - height) / 2).rounded()
        host.frame = CGRect(x: 0, y: 0, width: size.width, height: height)
        strip.frame = CGRect(x: strip.frame.minX, y: y, width: size.width, height: height)
        let half = size.width / 2
        if abs(half - width) > 0.5 {
            let phase = currentPhase()
            width = half
            run(from: phase)
        }
    }

    // currentPhase returns how far into one copy the row has scrolled.
    private func currentPhase() -> CGFloat {
        let shift: CGFloat
        if strip.layer?.animation(forKey: Self.key) != nil,
            let value = strip.layer?.presentation()?.value(forKeyPath: "transform.translation.x") as? CGFloat
        {
            shift = -value
        } else {
            shift = -strip.frame.minX
        }
        guard width > 0 else {
            return 0
        }
        let phase = shift.truncatingRemainder(dividingBy: width)
        return phase < 0 ? phase + width : phase
    }

    // run starts the scroll from the given phase, or holds the row there while the ticker is held.
    private func run(from phase: CGFloat) {
        guard let layer = strip.layer else {
            return
        }
        layer.removeAnimation(forKey: Self.key)
        guard width > 0, speed > 0, !held else {
            strip.frame.origin.x = -phase
            return
        }
        strip.frame.origin.x = 0
        let duration = Double(width) / speed
        let animation = CABasicAnimation(keyPath: "transform.translation.x")
        animation.fromValue = 0
        animation.toValue = -width
        animation.duration = duration
        animation.repeatCount = .infinity
        animation.timeOffset = Double(phase) / speed
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

    // mouseEntered holds the ticker.
    override func mouseEntered(with event: NSEvent) {
        let phase = currentPhase()
        hovered = true
        run(from: phase)
    }

    // mouseExited lets the ticker run again.
    override func mouseExited(with event: NSEvent) {
        let phase = currentPhase()
        hovered = false
        run(from: phase)
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
        guard width > 0 else {
            return
        }
        let point = convert(event.locationInWindow, from: nil)
        var x = (point.x + currentPhase()).truncatingRemainder(dividingBy: width)
        if x < 0 {
            x += width
        }
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

// MarqueeRow lays out every entry twice, side by side.
struct MarqueeRow: View {
    // entries are the headlines to lay out.
    let entries: [Entry]
    // font draws the headlines.
    let font: Font
    // color draws the headlines, or nil for the primary label color.
    let color: Color?
    // spans receives where each headline sits in the first copy.
    let spans: Spans

    // space names the row's coordinate space.
    nonisolated private static let space = "row"

    // body draws both copies.
    var body: some View {
        HStack(spacing: 0) {
            copy(report: true)
            copy(report: false)
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
