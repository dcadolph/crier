import AppKit
import SwiftUI

import CrierKit

// SettingsTab names one page of the settings window.
enum SettingsTab: String, CaseIterable, Identifiable {
    case ticker
    case sources
    case colors
    case follows
    case feeds
    case alerts
    case general

    // id identifies the tab in lists.
    var id: Self { self }

    // title is the tab's label.
    var title: String {
        switch self {
        case .ticker: "Ticker"
        case .sources: "Sources"
        case .colors: "Colors"
        case .follows: "Follows"
        case .feeds: "Feeds"
        case .alerts: "Alerts"
        case .general: "General"
        }
    }

    // symbol is the tab's SF Symbol.
    var symbol: String {
        switch self {
        case .ticker: "text.line.first.and.arrowtriangle.forward"
        case .sources: "newspaper"
        case .colors: "paintpalette"
        case .follows: "star"
        case .feeds: "dot.radiowaves.up.forward"
        case .alerts: "bell.badge"
        case .general: "gearshape"
        }
    }
}

// SettingsView is the settings window's content: the bell and wordmark over tabbed pages. Every change applies
// right away.
struct SettingsView: View {
    // store holds the live settings.
    @Bindable var store: SettingsStore
    // news holds the headlines and feed failures.
    var news: News
    // loginItem starts Crier at login.
    var loginItem: LoginItem
    // tab is the page on show.
    @State private var tab: SettingsTab = .ticker
    // trusted reports whether Crier may read the app menus, checked while the ticker page is open.
    @State private var trusted = BarRoom.trusted

    // body draws the header over the tabs.
    var body: some View {
        VStack(spacing: 0) {
            Header()
            TabView(selection: $tab) {
                ForEach(SettingsTab.allCases) { tab in
                    page(tab)
                        .tabItem { Label(tab.title, systemImage: tab.symbol) }
                        .tag(tab)
                }
            }
            .padding(16)
        }
        .frame(width: 560, height: 560)
    }

    // page draws one tab's form.
    @ViewBuilder
    private func page(_ tab: SettingsTab) -> some View {
        switch tab {
        case .ticker: tickerPage
        case .sources: sourcesPage
        case .colors: colorsPage
        case .follows: followsPage
        case .feeds: feedsPage
        case .alerts: alertsPage
        case .general: generalPage
        }
    }

    // tickerPage sets where the ticker sits and how it moves.
    private var tickerPage: some View {
        Form {
            Toggle("Show the ticker", isOn: $store.settings.tickerOn)
            Picker("Place", selection: $store.settings.place) {
                ForEach(Place.allCases, id: \.self) { place in
                    Text(place.title).tag(place)
                }
            }
            if store.settings.place == .menuBar {
                Picker("Position", selection: $store.settings.position) {
                    ForEach(Position.allCases, id: \.self) { position in
                        Text(position.title).tag(position)
                    }
                }
                Toggle("Fill the open bar", isOn: $store.settings.fill)
                if !store.settings.fill {
                    LabeledContent("Width") {
                        Slider(value: $store.settings.width, in: 240...1200, step: 20)
                        Text("\(Int(store.settings.width)) pt").monospacedDigit().frame(width: 60, alignment: .trailing)
                    }
                }
                LabeledContent("Offset") {
                    Slider(value: $store.settings.offset, in: -800...800, step: 10)
                    Text("\(Int(store.settings.offset)) pt").monospacedDigit().frame(width: 60, alignment: .trailing)
                }
                if trusted {
                    LabeledContent("App menus", value: "Tracked")
                } else {
                    LabeledContent("Room for app menus") {
                        Slider(value: $store.settings.menuRoom, in: 200...2000, step: 20)
                        Text("\(Int(store.settings.menuRoom)) pt").monospacedDigit()
                            .frame(width: 60, alignment: .trailing)
                    }
                    LabeledContent("Track the menus exactly") {
                        Button("Allow Accessibility…") {
                            BarRoom.askForTrust()
                        }
                    }
                }
                Text("The ticker steps around the notch and Fuginaut's clock, and stays clear of the status icons.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            LabeledContent("Speed") {
                Slider(value: $store.settings.speed, in: 5...200, step: 5) {
                    EmptyView()
                } minimumValueLabel: {
                    Image(systemName: "tortoise")
                } maximumValueLabel: {
                    Image(systemName: "hare")
                }
                Text("\(Int(store.settings.speed)) pt/s").monospacedDigit().frame(width: 60, alignment: .trailing)
            }
            Toggle("Match the menu bar's text color", isOn: matchBarBinding)
            if let color = store.settings.tickerColor {
                ColorPicker(
                    "Text color",
                    selection: Binding(get: { color.color }, set: { store.settings.tickerColor = StoredColor($0) }))
            }
            Toggle("Show on every display", isOn: $store.settings.allDisplays)
            Text("Hover over the ticker to hold it still. Click a headline to open it.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .task {
            while !Task.isCancelled {
                trusted = BarRoom.trusted
                try? await Task.sleep(for: BarRoom.interval)
            }
        }
    }

    // sourcesPage turns topics and the single feeds under them on and off.
    private var sourcesPage: some View {
        Form {
            ForEach(Topic.choosable, id: \.self) { topic in
                Section {
                    Toggle(isOn: topicBinding(topic)) {
                        Text(topic.title).fontWeight(.semibold)
                    }
                    ForEach(Source.catalog.filter { $0.topic == topic }) { source in
                        sourceToggle(source)
                            .padding(.leading, 16)
                            .disabled(!store.settings.topics.contains(topic))
                    }
                }
            }
            Section {
                ForEach(Source.catalog.filter(\.topic.muted)) { source in
                    sourceToggle(source)
                }
            } header: {
                Text("Screening")
            } footer: {
                Text(
                    "These feeds never fill the ticker. They keep entertainment and sports out of it unless a "
                        + "story is major. Turn one off to stop screening its stories."
                )
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // colorsPage picks the news band's colors and how long each page of top stories stays up.
    private var colorsPage: some View {
        Form {
            Picker("News band", selection: $store.settings.look) {
                ForEach(Look.allCases, id: \.self) { look in
                    Text(look.title).tag(look)
                }
            }
            BandSample(theme: store.settings.theme)
            if store.settings.look == .custom {
                ColorPicker("Background", selection: colorBinding(\.background), supportsOpacity: false)
                ColorPicker("Text", selection: colorBinding(\.text), supportsOpacity: false)
                ColorPicker("Major stories", selection: colorBinding(\.accent), supportsOpacity: false)
            }
            LabeledContent("Next page every") {
                Slider(value: $store.settings.rotationSeconds, in: 10...120, step: 5)
                Text("\(Int(store.settings.rotationSeconds)) s").monospacedDigit().frame(
                    width: 60, alignment: .trailing)
            }
            Text("The band tops Crier's window, open from the bell menu. Changes show there right away.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }

    // followsPage edits the teams and subjects kept in the ticker.
    private var followsPage: some View {
        Form {
            Section {
                ForEach(store.settings.follows.indices, id: \.self) { index in
                    HStack {
                        TextField("Name", text: $store.settings.follows[index].name)
                            .frame(width: 110)
                        TextField("Search", text: $store.settings.follows[index].query)
                        Button {
                            store.settings.follows.remove(at: index)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                    }
                    .labelsHidden()
                }
                Button("Add Follow") {
                    store.settings.follows.append(Follow(name: "", query: ""))
                }
            } footer: {
                Text(
                    "Each follow searches Google News. Put a phrase in quotes for an exact match. "
                        + "A headline only shows when it names the follow."
                )
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // feedsPage edits the reader's own RSS and Atom feeds.
    private var feedsPage: some View {
        Form {
            Section {
                ForEach(store.settings.feeds.indices, id: \.self) { index in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            TextField("Name", text: $store.settings.feeds[index].name)
                                .frame(width: 110)
                            TextField("https://example.com/feed.xml", text: $store.settings.feeds[index].url)
                            Button {
                                store.settings.feeds.remove(at: index)
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                        }
                        .labelsHidden()
                        if let reason = failure(store.settings.feeds[index]) {
                            FailureNote(reason: reason)
                        }
                    }
                }
                Button("Add Feed") {
                    store.settings.feeds.append(CustomFeed(name: "", url: ""))
                }
            } footer: {
                Text("Any RSS or Atom address works. Its stories rank alongside the top stories.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // alertsPage sets when a major story interrupts.
    private var alertsPage: some View {
        Form {
            Toggle("Alert me to major stories", isOn: $store.settings.alerts.enabled)
            Stepper(value: $store.settings.alerts.minOutlets, in: 2...15) {
                LabeledContent("Major at", value: "\(store.settings.alerts.minOutlets) outlets")
            }
            Stepper(value: $store.settings.alerts.dailyCap, in: 1...20) {
                LabeledContent("At most", value: "\(store.settings.alerts.dailyCap) a day")
            }
            Picker("Quiet from", selection: $store.settings.alerts.quietStart) {
                ForEach(0..<24, id: \.self) { hour in
                    Text(hourText(hour)).tag(hour)
                }
            }
            Picker("Quiet until", selection: $store.settings.alerts.quietEnd) {
                ForEach(0..<24, id: \.self) { hour in
                    Text(hourText(hour)).tag(hour)
                }
            }
            Stepper(value: $store.settings.alerts.maxAgeHours, in: 1...24, step: 1) {
                LabeledContent("Skip stories older than", value: "\(Int(store.settings.alerts.maxAgeHours)) h")
            }
            Text("A story is major when that many separate outlets carry it. Majors get a red dot in the ticker.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }

    // generalPage holds login, the refresh interval, and feed health.
    private var generalPage: some View {
        Form {
            Toggle(
                "Open at login",
                isOn: Binding(get: { loginItem.isEnabled }, set: { loginItem.setEnabled($0) })
            )
            if loginItem.needsApproval {
                Text("Allow Crier in System Settings, General, Login Items.")
                    .foregroundStyle(.secondary)
            }
            if let error = loginItem.lastError {
                Text(error).foregroundStyle(.red)
            }
            Stepper(value: $store.settings.refreshMinutes, in: 1...60, step: 1) {
                LabeledContent("Read the news every", value: "\(Int(store.settings.refreshMinutes)) min")
            }
            LabeledContent("Last read", value: news.updated?.formatted(date: .omitted, time: .shortened) ?? "Not yet")
            LabeledContent("Headlines", value: "\(news.headlines.count)")
            if !news.failures.isEmpty {
                LabeledContent("Failed feeds", value: failedNames)
            }
            HStack {
                Button("Refresh Now") {
                    Task { await news.refresh() }
                }
                .disabled(news.refreshing)
                Spacer()
                Button("Restore Defaults") {
                    store.reset()
                }
                Button("Quit Crier") {
                    NSApp.terminate(nil)
                }
            }
        }
        .formStyle(.grouped)
    }

    // sourceToggle switches one catalog feed on or off, with a warning when its last read failed.
    private func sourceToggle(_ source: Source) -> some View {
        Toggle(
            isOn: Binding(
                get: { !store.settings.disabledSources.contains(source.id) },
                set: { on in
                    if on {
                        store.settings.disabledSources.remove(source.id)
                    } else {
                        store.settings.disabledSources.insert(source.id)
                    }
                }
            )
        ) {
            VStack(alignment: .leading, spacing: 2) {
                Text(source.name)
                if let reason = news.failures[source.id] {
                    FailureNote(reason: reason)
                }
            }
        }
    }

    // matchBarBinding switches the ticker between the menu bar's text color and a color of its own.
    private var matchBarBinding: Binding<Bool> {
        Binding(
            get: { store.settings.tickerColor == nil },
            set: { match in
                store.settings.tickerColor = match ? nil : StoredColor(Color(nsColor: .labelColor))
            }
        )
    }

    // colorBinding edits one of the custom band colors.
    private func colorBinding(_ path: WritableKeyPath<CustomLook, StoredColor>) -> Binding<Color> {
        Binding(
            get: { store.settings.customLook[keyPath: path].color },
            set: { store.settings.customLook[keyPath: path] = StoredColor($0) }
        )
    }

    // topicBinding switches one topic on or off.
    private func topicBinding(_ topic: Topic) -> Binding<Bool> {
        Binding(
            get: { store.settings.topics.contains(topic) },
            set: { on in
                if on {
                    store.settings.topics.insert(topic)
                } else {
                    store.settings.topics.remove(topic)
                }
            }
        )
    }

    // failedNames lists the feeds whose last read failed, by name.
    private var failedNames: String {
        let names = Dictionary(store.settings.sources.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        return news.failures.keys.map { names[$0] ?? $0 }.sorted().joined(separator: ", ")
    }

    // failure returns why a custom feed's last read failed, if it did.
    private func failure(_ feed: CustomFeed) -> String? {
        guard let id = feed.source?.id else {
            return feed.url.isEmpty ? nil : "Not a web address."
        }
        return news.failures[id]
    }

    // hourText names an hour of the day in the reader's clock style.
    private func hourText(_ hour: Int) -> String {
        let date = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date()) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }
}

// FailureNote explains why a feed's last read failed, in orange under the feed's name.
struct FailureNote: View {
    // reason is the failure in plain words.
    let reason: String

    // body draws the warning sign and the reason.
    var body: some View {
        Label(reason, systemImage: "exclamationmark.triangle")
            .font(.caption)
            .foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// BandSample previews the news band's colors with one sample story.
struct BandSample: View {
    // theme colors the sample, or nil to follow light and dark mode.
    let theme: BandTheme?

    // scheme picks the default theme.
    @Environment(\.colorScheme) private var scheme

    // body draws the sample.
    var body: some View {
        let theme = theme ?? (scheme == .dark ? .dark : .light)
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Circle().fill(theme.accent).frame(width: 7, height: 7)
                Text("MAJOR").font(.system(size: 10, weight: .bold)).foregroundStyle(theme.accent)
                Text("THE TOWN CRIER").font(.system(size: 10, weight: .semibold)).tracking(0.6)
                    .foregroundStyle(theme.foreground.opacity(0.6))
            }
            Text("Hear ye, hear ye: the news band wears your colors")
                .font(.system(size: 16, weight: .semibold, design: .serif))
                .foregroundStyle(theme.foreground)
            Text("9 outlets · just now").font(.system(size: 11)).foregroundStyle(theme.foreground.opacity(0.6))
            Rectangle().fill(theme.accent.opacity(0.75)).frame(width: 140, height: 2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.background, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(theme.foreground.opacity(0.12)))
    }
}

// Header is the band atop the settings window: the bell and the CRIER wordmark on ink. It keeps its ink in
// light and dark mode because it is artwork, not chrome.
struct Header: View {
    // ink is the band's color, the app icon's tile.
    static let ink = Color(red: 32 / 255, green: 31 / 255, blue: 29 / 255)
    // paper is the wordmark's color.
    static let paper = Color(red: 0.96, green: 0.93, blue: 0.86)
    // bell is the bell cutout from the app bundle.
    private let bell = Bundle.main.image(forResource: "bell")

    // body draws the band.
    var body: some View {
        HStack(spacing: 14) {
            if let bell {
                Image(nsImage: bell)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(height: 64)
            }
            Text("CRIER")
                .font(.system(size: 40, weight: .semibold, design: .serif))
                .tracking(6)
                .foregroundStyle(Self.paper)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 104)
        .background(Self.ink)
    }
}
