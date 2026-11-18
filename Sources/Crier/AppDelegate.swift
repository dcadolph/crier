import AppKit
import SwiftUI

import CrierKit

// AppDelegate starts Crier and owns its long-lived objects.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    // store holds the live settings.
    private let store = SettingsStore()
    // loginItem starts Crier at login.
    private let loginItem = LoginItem()
    // news reads the feeds and keeps the headlines.
    private var news: News?
    // notifier posts major story alerts.
    private var notifier: Notifier?
    // ticker draws the ticker on every display that shows it.
    private var ticker: TickerPanels?
    // statusItem is the menu bar bell.
    private var statusItem: StatusItemController?
    // newsWindow is Crier's own window.
    private var newsWindow: NewsWindow?
    // settingsWindow is created on first open and reused.
    private var settingsWindow: NSWindow?
    // pending is a refresh waiting for the reader to stop editing feeds or follows.
    private var pending: Task<Void, Never>?

    // settle is how long after the last feed or follow edit the news is read again.
    static let settle = Duration.seconds(1.5)

    // applicationDidFinishLaunching starts reading the news, draws the ticker, and adds the bell.
    func applicationDidFinishLaunching(_ notification: Notification) {
        loginItem.configureOnFirstLaunch()
        let news = News(settings: store.settings)
        let notifier = Notifier(store: store)
        news.onRefresh = { [weak notifier] headlines, first in
            notifier?.handle(headlines, first: first)
        }
        store.onChange { [weak self] old in
            self?.settingsChanged(from: old)
        }
        self.news = news
        self.notifier = notifier
        ticker = TickerPanels(store: store, news: news)
        let newsWindow = NewsWindow(store: store, news: news)
        self.newsWindow = newsWindow
        let statusItem = StatusItemController(
            store: store, news: news, openNews: { [weak newsWindow] in newsWindow?.show() },
            openSettings: { [weak self] in self?.showSettings() })
        statusItem.watchBarAppearance { [weak self] appearance in
            self?.ticker?.barAppearance = appearance
        }
        self.statusItem = statusItem
        news.start()
    }

    // applicationShouldHandleReopen opens Crier's window when Crier is opened again.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        newsWindow?.show()
        return false
    }

    // settingsChanged hands the settings to the news and reads the feeds again shortly after the feeds,
    // follows, or alert rules change.
    private func settingsChanged(from old: CrierKit.Settings) {
        guard let news else {
            return
        }
        let new = store.settings
        news.settings = new
        guard old.sources != new.sources || old.follows != new.follows || old.alerts != new.alerts else {
            return
        }
        pending?.cancel()
        pending = Task { [weak news] in
            try? await Task.sleep(for: Self.settle)
            guard !Task.isCancelled else {
                return
            }
            await news?.refresh()
        }
    }

    // showSettings opens the settings window and brings it to the front.
    private func showSettings() {
        guard let news else {
            return
        }
        if settingsWindow == nil {
            let host = NSHostingController(rootView: SettingsView(store: store, news: news, loginItem: loginItem))
            let window = NSWindow(contentViewController: host)
            window.title = "Crier Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        loginItem.refresh()
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
