import AppKit
import SwiftUI

import CrierKit

// NewsWindow is Crier's own window: the news band on top and every headline listed below it.
@MainActor
final class NewsWindow {
    // window is created on first open and reused.
    private var window: NSWindow?
    // store holds the live settings.
    private let store: SettingsStore
    // news holds the headlines.
    private let news: News

    // init remembers what the window shows.
    init(store: SettingsStore, news: News) {
        self.store = store
        self.news = news
    }

    // show opens the window and brings it to the front.
    func show() {
        if window == nil {
            let host = NSHostingController(rootView: NewsWindowView(store: store, news: news))
            host.sizingOptions = []
            let window = NSWindow(contentViewController: host)
            window.title = "Crier"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.contentMinSize = NSSize(width: 760, height: 480)
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 1240, height: 820))
            window.center()
            window.setFrameAutosaveName("CrierNews")
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

// NewsWindowView lays out the band over the full headline list.
struct NewsWindowView: View {
    // store holds the live settings.
    let store: SettingsStore
    // news holds the headlines.
    let news: News

    // bell is the app's bell cutout, drawn beside the band's wordmark.
    private static let bell = Bundle.main.image(forResource: "bell").map { Image(nsImage: $0) }

    // body draws the band and the list.
    var body: some View {
        VStack(spacing: 0) {
            NewsBand(
                entries: news.entries, theme: store.drawn.theme, mark: Self.bell,
                rotation: .seconds(store.settings.rotationSeconds), speed: store.settings.speed
            )
            .padding(12)
            Divider()
            HeadlineList(entries: news.listed)
        }
    }
}
