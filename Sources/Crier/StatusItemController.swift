import AppKit

import CrierKit

// StatusItemController owns the menu bar bell and its menu: the top headlines, Crier's window, the ticker
// switch, a refresh, when the news was last read, settings, and quit.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    // item is the menu bar icon.
    private let item: NSStatusItem
    // store holds the live settings.
    private let store: SettingsStore
    // news holds the headlines.
    private let news: News
    // openNews opens Crier's window.
    private let openNews: () -> Void
    // openSettings opens the settings window.
    private let openSettings: () -> Void
    // appearanceWatch follows the menu bar's appearance through the bell's button.
    private var appearanceWatch: NSKeyValueObservation?

    // menuHeadlines is how many headlines the menu lists.
    static let menuHeadlines = 10
    // titleLimit is the longest headline the menu shows before cutting it short.
    static let titleLimit = 80

    // init adds the icon and its menu.
    init(store: SettingsStore, news: News, openNews: @escaping () -> Void, openSettings: @escaping () -> Void) {
        self.store = store
        self.news = news
        self.openNews = openNews
        self.openSettings = openSettings
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        let glyph = Bundle.main.image(forResource: "glyph")
        glyph?.isTemplate = true
        glyph?.size = NSSize(width: 18, height: 18)
        item.button?.image = glyph ?? NSImage(systemSymbolName: "bell", accessibilityDescription: "Crier")
        item.button?.toolTip = "Crier"
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        item.menu = menu
    }

    // alarm turns the bell red while an emergency is in force, orange while only a watch or an ordinary warning
    // is, and back to the bar's own color after.
    func alarm(_ tier: Tier) {
        switch tier {
        case .none:
            item.button?.contentTintColor = nil
            item.button?.toolTip = "Crier"
        case .orange:
            item.button?.contentTintColor = .systemOrange
            item.button?.toolTip = "Crier: watch or warning in force"
        case .red, .top:
            item.button?.contentTintColor = .systemRed
            item.button?.toolTip = "Crier: emergency in force"
        }
    }

    // bellFrame returns the bell's frame in screen coordinates, or nil when macOS keeps it out of the bar.
    var bellFrame: NSRect? {
        guard let window = item.button?.window, window.isVisible, item.isVisible else {
            return nil
        }
        return window.frame
    }

    // watchBarAppearance calls handler now and whenever the menu bar switches between light and dark text. The
    // bell's button takes on the menu bar's own appearance, which follows the wallpaper as well as the system
    // theme, so it is the same signal macOS uses for the bar's text.
    func watchBarAppearance(_ handler: @escaping @MainActor (NSAppearance) -> Void) {
        appearanceWatch = item.button?.observe(\.effectiveAppearance, options: [.initial, .new]) { button, _ in
            MainActor.assumeIsolated {
                handler(button.effectiveAppearance)
            }
        }
    }

    // menuNeedsUpdate rebuilds the menu each time it opens, so it always shows the latest news.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let entries = news.entries.prefix(Self.menuHeadlines)
        if entries.isEmpty {
            menu.addItem(disabled("No headlines yet"))
        }
        for entry in entries {
            let headline = NSMenuItem(title: "", action: #selector(openHeadline), keyEquivalent: "")
            headline.attributedTitle = title(entry)
            headline.target = self
            headline.representedObject = entry.headline.lead.link
            headline.toolTip = "\(entry.headline.lead.outlet), \(entry.headline.outlets.count) outlets"
            menu.addItem(headline)
        }
        menu.addItem(.separator())
        let window = NSMenuItem(title: "Open Crier", action: #selector(newsChosen), keyEquivalent: "o")
        window.target = self
        menu.addItem(window)
        let ticker = NSMenuItem(title: "Show Ticker", action: #selector(toggleTicker), keyEquivalent: "t")
        ticker.target = self
        ticker.state = store.settings.tickerOn ? .on : .off
        menu.addItem(ticker)
        let refresh = NSMenuItem(title: "Refresh Now", action: #selector(refreshNow), keyEquivalent: "r")
        refresh.target = self
        refresh.isEnabled = !news.refreshing
        menu.addItem(refresh)
        menu.addItem(disabled(updatedText()))
        menu.addItem(.separator())
        let settings = NSMenuItem(title: "Settings…", action: #selector(settingsChosen), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(NSMenuItem(title: "Quit Crier", action: #selector(NSApp.terminate), keyEquivalent: "q"))
    }

    // title is a headline's menu text, with a red dot for a major story and the follow's name before a
    // followed one.
    private func title(_ entry: Entry) -> NSAttributedString {
        var text = entry.headline.lead.title
        if text.count > Self.titleLimit {
            text = String(text.prefix(Self.titleLimit - 1)).trimmingCharacters(in: .whitespaces) + "…"
        }
        if let tag = entry.tag {
            text = "\(tag): \(text)"
        }
        let font = NSFont.menuFont(ofSize: 0)
        let title = NSMutableAttributedString(string: text, attributes: [.font: font])
        if entry.major {
            let dot = NSAttributedString(
                string: "\u{25CF} ", attributes: [.font: font, .foregroundColor: NSColor.systemRed])
            title.insert(dot, at: 0)
        }
        return title
    }

    // updatedText says when the news was last read.
    private func updatedText() -> String {
        if news.refreshing {
            return "Reading the news…"
        }
        guard let updated = news.updated else {
            return "Not read yet"
        }
        var text = "Updated \(updated.formatted(date: .omitted, time: .shortened))"
        if !news.failures.isEmpty {
            text += ", \(news.failures.count) feeds failed"
        }
        return text
    }

    // disabled builds a menu item that only shows text.
    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    // openHeadline opens the chosen headline's link.
    @objc private func openHeadline(_ sender: NSMenuItem) {
        if let url = sender.representedObject as? URL {
            NSWorkspace.shared.open(url)
        }
    }

    // toggleTicker shows or hides the ticker.
    @objc private func toggleTicker() {
        store.settings.tickerOn.toggle()
    }

    // refreshNow reads the feeds at once.
    @objc private func refreshNow() {
        Task {
            await news.refresh()
        }
    }

    // newsChosen opens Crier's window.
    @objc private func newsChosen() {
        openNews()
    }

    // settingsChosen opens the settings window.
    @objc private func settingsChosen() {
        openSettings()
    }
}
