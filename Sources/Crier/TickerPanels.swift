import AppKit
import SwiftUI

import CrierKit

// TickerPanels keeps one ticker panel on every display that shows the ticker.
@MainActor
final class TickerPanels: NSObject {
    // store holds the live settings.
    private let store: SettingsStore
    // news holds the ticker entries.
    private let news: News
    // room measures what else takes space in the menu bar.
    private let room: BarRoom
    // panels holds one panel per display, keyed by display number.
    private var panels: [CGDirectDisplayID: TickerPanel] = [:]
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

    // layout places a panel on every display that shows the ticker and removes the rest.
    @objc func layout() {
        let settings = store.settings
        var seen = Set<CGDirectDisplayID>()
        for display in settings.tickerOn ? Display.shown(settings) : [] {
            seen.insert(display.id)
            let panel = panels[display.id] ?? makePanel(display.id)
            panel.appearance = settings.place == .menuBar ? barAppearance : nil
            panel.show(frame: Placement.frame(bar: display.bar(), settings: settings, room: room.room))
        }
        for (id, panel) in panels where !seen.contains(id) {
            panel.orderOut(nil)
            panels[id] = nil
        }
    }

    // makePanel builds and records a panel for a display.
    private func makePanel(_ id: CGDirectDisplayID) -> TickerPanel {
        let panel = TickerPanel(store: store, news: news)
        panels[id] = panel
        return panel
    }
}

// TickerPanel is a clear panel at status bar level on every space that holds the ticker. It takes the mouse,
// so hovering holds the ticker and a click opens a headline, but it never takes keyboard focus.
@MainActor
final class TickerPanel: NSPanel {
    // init builds the panel.
    init(store: SettingsStore, news: News) {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        contentView = NSHostingView(rootView: TickerRoot(store: store, news: news))
    }

    // canBecomeKey keeps the panel from ever taking keyboard focus.
    override var canBecomeKey: Bool {
        false
    }

    // show places the panel, or hides it when there is no frame because the menu bar is hidden.
    func show(frame: CGRect?) {
        guard let frame else {
            orderOut(nil)
            return
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

    // body draws the ticker.
    var body: some View {
        let strip = store.settings.place == .belowMenuBar
        TickerView(entries: news.entries, speed: store.settings.speed, color: store.settings.tickerColor?.color)
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
