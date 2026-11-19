import AppKit
import SwiftUI

import CrierKit

// TickerPanels keeps the ticker panels on every display that shows the ticker: one per open stretch of the bar,
// all on one clock per display, so a ticker split by Fuginaut's clock scrolls as one row.
@MainActor
final class TickerPanels: NSObject {
    // store holds the live settings.
    private let store: SettingsStore
    // news holds the ticker entries.
    private let news: News
    // siren holds the emergency in force.
    private let siren: Siren
    // room measures what else takes space in the menu bar.
    private let room: BarRoom
    // panels holds each display's panels, left to right, keyed by display number.
    private var panels: [CGDirectDisplayID: [TickerPanel]] = [:]
    // clocks holds each display's shared scroll, keyed by display number.
    private var clocks: [CGDirectDisplayID: MarqueeClock] = [:]
    // barAppearance is the menu bar's appearance, which the ticker takes in the menu bar so its text reads like
    // the bar's own. The strip keeps the system appearance, since it draws its own backing.
    var barAppearance: NSAppearance? {
        didSet {
            layout()
        }
    }

    // init places the panels and follows display, space, and settings changes.
    init(store: SettingsStore, news: News, siren: Siren, room: BarRoom) {
        self.store = store
        self.news = news
        self.siren = siren
        self.room = room
        super.init()
        room.onChange = { [weak self] in
            self?.layout()
        }
        NotificationCenter.default.addObserver(
            self, selector: #selector(layout), name: NSApplication.didChangeScreenParametersNotification, object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(layout), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil
        )
        store.onChange { [weak self] _ in
            self?.layout()
        }
        layout()
    }

    // layout places a panel in every open stretch on every display that shows the ticker and removes the rest.
    @objc func layout() {
        let settings = store.settings
        var seen = Set<CGDirectDisplayID>()
        for display in settings.tickerOn ? Display.shown(settings) : [] {
            seen.insert(display.id)
            let bar = display.bar()
            let frames = Placement.frames(bar: bar, settings: settings, room: room.room)
            let clock = clocks[display.id] ?? MarqueeClock()
            clocks[display.id] = clock
            var list = panels[display.id] ?? []
            while list.count < frames.count {
                list.append(TickerPanel(store: store, news: news, siren: siren, clock: clock))
            }
            while list.count > frames.count {
                list.removeLast().retire()
            }
            for (index, (panel, frame)) in zip(list, frames).enumerated() {
                panel.appearance = settings.place == .menuBar ? barAppearance : nil
                panel.show(frame: frame, offset: frame.minX - bar.frame.minX, lead: index == 0)
            }
            panels[display.id] = list
        }
        for id in panels.keys where !seen.contains(id) {
            panels[id]?.forEach { $0.retire() }
            panels[id] = nil
            clocks[id] = nil
        }
    }
}

// TickerPanel is a clear panel at status bar level on every space that holds the ticker. It takes the mouse,
// so hovering holds the ticker and a click opens a headline, but it never takes keyboard focus.
@MainActor
final class TickerPanel: NSPanel {
    // host draws the ticker.
    private let host: NSHostingView<TickerRoot>

    // init builds the panel on the display's shared clock.
    init(store: SettingsStore, news: News, siren: Siren, clock: MarqueeClock) {
        host = NSHostingView(
            rootView: TickerRoot(store: store, news: news, siren: siren, offset: 0, lead: false, clock: clock))
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        contentView = host
    }

    // canBecomeKey keeps the panel from ever taking keyboard focus.
    override var canBecomeKey: Bool {
        false
    }

    // retire hides the panel for good and takes its ticker out, so the ticker leaves the shared clock even when
    // the mouse was over it.
    func retire() {
        orderOut(nil)
        contentView = nil
    }

    // show places the panel and tells its ticker where it sits along the display's row and whether it is the
    // display's leftmost panel, which carries the pinned emergency line.
    func show(frame: CGRect, offset: CGFloat, lead: Bool) {
        let root = host.rootView
        if root.offset != offset || root.lead != lead {
            host.rootView = TickerRoot(
                store: root.store, news: root.news, siren: root.siren, offset: offset, lead: lead, clock: root.clock)
        }
        setFrame(frame, display: true)
        orderFrontRegardless()
    }
}

// TickerRoot is a ticker panel's content: the ticker, on a bar backing when it sits in the strip. The display's
// leftmost panel pins the emergency line over the left end of the row, so the shared scroll keeps its place. For a
// watch or an ordinary warning the line sits on an orange tab and the ticker keeps its look. From the red tier up
// the panel turns red with white type.
struct TickerRoot: View {
    // store holds the live settings.
    let store: SettingsStore
    // news holds the ticker entries.
    let news: News
    // siren holds the emergency in force.
    let siren: Siren
    // offset is the panel's left edge measured from its display's left edge.
    let offset: CGFloat
    // lead reports whether this is the display's leftmost panel.
    let lead: Bool
    // clock is the scroll the display's panels share.
    let clock: MarqueeClock

    // reduceMotion follows the macOS Reduce Motion setting, which turns flashing off.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // emergencyRed fills the ticker during an emergency.
    static let emergencyRed = Color(.sRGB, red: 0.78, green: 0.06, blue: 0.08)
    // pinnedRed backs the pinned line from the red tier up.
    static let pinnedRed = Color(.sRGB, red: 0.5, green: 0.02, blue: 0.04)
    // noticeOrange backs the pinned line for a watch or an ordinary warning. It takes dark type, which reads
    // better on orange than white does.
    static let noticeOrange = Color(.sRGB, red: 0.98, green: 0.58, blue: 0.1)
    // pulse is how long each half of a flash takes. Three pulses take three seconds, well under the limit of three
    // flashes a second.
    static let pulse = 0.5

    // body draws the ticker.
    var body: some View {
        let strip = store.settings.place == .belowMenuBar
        let alarm = siren.tier >= .red
        TickerView(
            entries: news.entries, speed: store.settings.speed,
            color: alarm ? .white : store.settings.tickerColor?.color, offset: strip ? offset + 8 : offset,
            clock: clock
        )
        .padding(.horizontal, strip ? 8 : 0)
        .overlay(alignment: .leading) {
            if siren.tier > .none, lead, let pinned = siren.pinned {
                pinnedLine(pinned, quiet: siren.tier == .orange)
            }
        }
        .background {
            ZStack {
                if strip, !alarm {
                    Rectangle().fill(.bar)
                        .overlay(alignment: .bottom) {
                            Divider()
                        }
                }
                flashing(Rectangle().fill(Self.emergencyRed).opacity(alarm ? 1 : 0))
            }
        }
    }

    // pinnedLine draws the emergency line on a darker red tab, or on an orange tab when quiet. A click stops the
    // sound, or opens the warning's page once the sound has stopped.
    private func pinnedLine(_ text: String, quiet: Bool) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(quiet ? .black : .white)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .frame(maxHeight: .infinity)
            .background(quiet ? Self.noticeOrange : Self.pinnedRed)
            .contentShape(Rectangle())
            .onTapGesture {
                siren.click()
            }
            .help(siren.acknowledged ? "Open the details." : "Click to stop the sound.")
    }

    // flashing pulses a view three times on each top tier interruption, unless flashing is off in settings or
    // macOS Reduce Motion is on. The animator stays in place between emergencies, so the first ring of a new
    // emergency flashes too.
    private func flashing(_ view: some View) -> some View {
        let flash = store.settings.emergency.flashing && !reduceMotion && siren.tier == .top
        return view.phaseAnimator([1.0, 0.25, 1.0, 0.25, 1.0, 0.25], trigger: siren.rings) { content, phase in
            content.opacity(flash ? phase : 1)
        } animation: { _ in
            .easeInOut(duration: Self.pulse)
        }
    }
}
