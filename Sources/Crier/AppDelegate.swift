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
    // feed polls the Weather Service for warnings at the reader's spot.
    private let feed = EmergencyFeed()
    // locator finds the reader's spot.
    private let locator = Locator()
    // siren interrupts for emergencies.
    private var siren: Siren?
    // relocating is a ZIP code lookup waiting for the reader to stop typing.
    private var relocating: Task<Void, Never>?
    // ticker draws the ticker on every display that shows it.
    private var ticker: TickerPanels?
    // room measures what else takes space in the menu bar.
    private var room: BarRoom?
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
        let siren = Siren(store: store, notifier: notifier)
        self.siren = siren
        news.onRefresh = { [weak self, weak notifier] headlines, first in
            notifier?.handle(headlines, first: first)
            if self?.store.settings.emergency.mode == .localAndNational {
                self?.siren?.read(headlines, first: first)
            }
        }
        store.onChange { [weak self] old in
            self?.settingsChanged(from: old)
        }
        self.news = news
        self.notifier = notifier
        let newsWindow = NewsWindow(store: store, news: news)
        self.newsWindow = newsWindow
        let statusItem = StatusItemController(
            store: store, news: news, openNews: { [weak newsWindow] in newsWindow?.show() },
            openSettings: { [weak self] in self?.showSettings() })
        self.statusItem = statusItem
        let room = BarRoom(store: store) { [weak statusItem] in statusItem?.bellFrame }
        self.room = room
        ticker = TickerPanels(store: store, news: news, siren: siren, room: room)
        startEmergencies(siren: siren, statusItem: statusItem)
        statusItem.watchBarAppearance { [weak self] appearance in
            self?.ticker?.barAppearance = appearance
        }
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
        emergencySettingsChanged(from: old.emergency, to: new.emergency)
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

    // startEmergencies wires the spot to the Weather Service feed, the feed to the siren, and the siren to the
    // bell, then starts polling when emergency mode is on.
    private func startEmergencies(siren: Siren, statusItem: StatusItemController) {
        locator.onSpot = { [weak self] spot in
            guard let self else {
                return
            }
            self.feed.spot = spot
            self.siren?.spot = spot
            Task { await self.feed.check() }
        }
        feed.onRing = { [weak self, weak siren] new in
            guard let self else {
                return
            }
            siren?.warn(self.feed.alerts, new: new)
        }
        watchAlarm(siren: siren, statusItem: statusItem)
        feed.sensitivity = store.settings.emergency.sensitivity
        if store.settings.emergency.mode != .off {
            locator.locate(zip: store.settings.emergency.zip)
            feed.start()
        }
    }

    // watchAlarm colors the bell for the emergency in force, hands the feed's warnings to the siren when they end,
    // and hands it the feed's notices whenever they change.
    private func watchAlarm(siren: Siren, statusItem: StatusItemController) {
        withObservationTracking {
            statusItem.alarm(siren.tier)
            if feed.alerts != siren.warnings {
                siren.warn(feed.alerts, new: [])
            }
            if feed.notices != siren.notices {
                siren.notice(feed.notices)
            }
        } onChange: { [weak self, weak siren, weak statusItem] in
            Task { @MainActor in
                guard let self, let siren, let statusItem else {
                    return
                }
                self.watchAlarm(siren: siren, statusItem: statusItem)
            }
        }
    }

    // emergencySettingsChanged starts or stops polling when emergency mode turns on or off, checks again when the
    // sensitivity changes, and looks up the area again shortly after the ZIP code stops changing.
    private func emergencySettingsChanged(from old: EmergencyRules, to new: EmergencyRules) {
        if new.sensitivity != old.sensitivity {
            feed.sensitivity = new.sensitivity
            if new.mode != .off, old.mode != .off {
                Task { await feed.check() }
            }
        }
        if new.mode == .off, old.mode != .off {
            feed.stop()
            siren?.clear()
            return
        }
        if new.mode != .off, old.mode == .off {
            locator.locate(zip: new.zip)
            feed.start()
            return
        }
        if new.mode == .local, old.mode == .localAndNational {
            siren?.read([], first: true)
        }
        guard new.mode != .off, new.zip != old.zip else {
            return
        }
        relocating?.cancel()
        relocating = Task { [weak self] in
            try? await Task.sleep(for: Self.settle)
            guard !Task.isCancelled else {
                return
            }
            self?.locator.locate(zip: new.zip)
        }
    }

    // showSettings opens the settings window and brings it to the front.
    private func showSettings() {
        guard let news, let siren else {
            return
        }
        if settingsWindow == nil {
            let host = NSHostingController(
                rootView: SettingsView(
                    store: store, news: news, loginItem: loginItem, siren: siren, feed: feed, locator: locator))
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
