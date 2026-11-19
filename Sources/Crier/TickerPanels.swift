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
    init(store: SettingsStore, news: News, room: BarRoom) {
        self.store = store
        self.news = news
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
                list.append(TickerPanel(store: store, news: news, clock: clock))
            }
            while list.count > frames.count {
                list.removeLast().retire()
            }
            for (panel, frame) in zip(list, frames) {
                panel.appearance = settings.place == .menuBar ? barAppearance : nil
                panel.show(frame: frame, offset: frame.minX - bar.frame.minX)
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
    init(store: SettingsStore, news: News, clock: MarqueeClock) {
        host = NSHostingView(rootView: TickerRoot(store: store, news: news, offset: 0, clock: clock))
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

    // show places the panel and tells its ticker where it sits along the display's row.
    func show(frame: CGRect, offset: CGFloat) {
        let root = host.rootView
        if root.offset != offset {
            host.rootView = TickerRoot(store: root.store, news: root.news, offset: offset, clock: root.clock)
        }
        setFrame(frame, display: true)
        orderFrontRegardless()
    }
}

// TickerRoot is a ticker panel's content: the ticker, on a bar backing when it sits in the strip.
struct TickerRoot: View {
    // store holds the live settings.
    let store: SettingsStore
    // news holds the ticker entries.
    let news: News
    // offset is the panel's left edge measured from its display's left edge.
    let offset: CGFloat
    // clock is the scroll the display's panels share.
    let clock: MarqueeClock

    // body draws the ticker.
    var body: some View {
        let strip = store.settings.place == .belowMenuBar
        TickerView(
            entries: news.entries, speed: store.settings.speed, color: store.settings.tickerColor?.color,
            offset: strip ? offset + 8 : offset, clock: clock
        )
        .padding(.horizontal, strip ? 8 : 0)
        .background {
            if strip {
                Rectangle().fill(.bar)
                    .overlay(alignment: .bottom) {
                        Divider()
                    }
            }
        }
    }
}
