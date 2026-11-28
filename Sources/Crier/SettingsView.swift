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
    case emergency
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
        case .emergency: "Emergency"
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
        case .emergency: "exclamationmark.triangle"
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
    // siren holds the emergency in force and runs the test.
    var siren: Siren
    // feed polls the Weather Service.
    var feed: EmergencyFeed
    // locator finds the reader's area.
    var locator: Locator
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
        case .emergency: emergencyPage
        case .general: generalPage
        }
    }

    // tickerPage sets where the ticker sits and how it moves.
    private var tickerPage: some View {
        Form {
            Toggle("Show the ticker", isOn: $store.settings.tickerOn)
                .help("Scroll headlines across the top of the screen. The bell menu works either way.")
            Picker("Place", selection: $store.settings.place) {
                ForEach(Place.allCases, id: \.self) { place in
                    Text(place.title).tag(place)
                }
            }
            .help(
                "In the menu bar fits the ticker into the bar's empty middle. Below the menu bar draws a full "
                    + "width strip under it, which covers the top of windows.")
            if store.settings.place == .menuBar {
                Picker("Position", selection: $store.settings.position) {
                    ForEach(Position.allCases, id: \.self) { position in
                        Text(position.title).tag(position)
                    }
                }
                .help("Where along the menu bar the ticker starts. Left of center leaves the middle to a clock.")
                Toggle("Fill the open bar", isOn: $store.settings.fill)
                    .help("Stretch the ticker across all the empty menu bar on its side, instead of a fixed width.")
                if !store.settings.fill {
                    LabeledContent("Width") {
                        Slider(value: $store.settings.width, in: 240...1200, step: 20)
                        Text("\(Int(store.settings.width)) pt").monospacedDigit().frame(width: 60, alignment: .trailing)
                    }
                    .help("How wide the ticker is, in points. It shrinks when the open bar is narrower.")
                }
                LabeledContent("Offset") {
                    Slider(value: $store.settings.offset, in: -800...800, step: 10)
                    Text("\(Int(store.settings.offset)) pt").monospacedDigit().frame(width: 60, alignment: .trailing)
                }
                .help("Nudge the ticker right, or left below zero, from its position. It still steps around the notch.")
                if trusted {
                    LabeledContent("App menus", value: "Tracked")
                        .help("Crier reads where each app's menus end, so the ticker never covers them.")
                } else {
                    LabeledContent("Room for app menus") {
                        Slider(value: $store.settings.menuRoom, in: 200...2000, step: 20)
                        Text("\(Int(store.settings.menuRoom)) pt").monospacedDigit()
                            .frame(width: 60, alignment: .trailing)
                    }
                    .help("How much of the bar's left end to keep clear for app menus, since Crier cannot see them.")
                    LabeledContent("Track the menus exactly") {
                        Button("Allow Accessibility…") {
                            BarRoom.askForTrust()
                        }
                    }
                    .help("Let Crier read where each app's menus end, so the room above is measured, not guessed.")
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
            .help("How fast headlines scroll, in points per second. The news band's ticker uses it too.")
            if store.theme != nil {
                Text(themeNote)
                    .foregroundStyle(.secondary)
            }
            Toggle("Match the menu bar's text color", isOn: matchBarBinding)
                .help("Draw headlines in the menu bar's own text color, which follows the wallpaper and theme.")
            if let color = store.settings.tickerColor {
                ColorPicker(
                    "Text color",
                    selection: Binding(get: { color.color }, set: { store.settings.tickerColor = StoredColor($0) })
                )
                .help("The color of the ticker's headlines.")
            }
            Toggle("Show on every display", isOn: $store.settings.allDisplays)
                .help("Put a ticker on each display's menu bar, not only the main one.")
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

    // sourcesPage sets how much of each topic to show and turns single feeds on and off.
    private var sourcesPage: some View {
        Form {
            Text(
                "More ranks a topic's stories higher and Less lower. Major only holds them back until enough "
                    + "outlets carry a story. Hover over a level for more."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            ForEach(Topic.choosable, id: \.self) { topic in
                Section {
                    Picker(selection: interestBinding(topic)) {
                        ForEach(Interest.allCases, id: \.self) { level in
                            Text(level.title).tag(level)
                        }
                    } label: {
                        Text(topic.title).fontWeight(.semibold)
                    }
                    .help(store.settings.level(topic).help)
                    ForEach(Source.catalog.filter { $0.topic == topic }) { source in
                        sourceToggle(source)
                            .padding(.leading, 16)
                            .disabled(store.settings.level(topic) == .off)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    // themeNote says a Mac-wide theme is drawing Crier, so the colors below wait until it is cleared.
    private let themeNote = "Your Mac's theme is drawing Crier's colors now. These come back when the theme is cleared."

    // colorsPage picks the news band's colors and how long each page of top stories stays up.
    private var colorsPage: some View {
        Form {
            Picker("News band", selection: $store.settings.look) {
                ForEach(Look.allCases, id: \.self) { look in
                    Text(look.title).tag(look)
                }
            }
            .help("The news band's colors. Match follows light and dark mode, Ink and Paper stay fixed.")
            if store.theme != nil {
                Text(themeNote)
                    .foregroundStyle(.secondary)
            }
            BandSample(theme: store.settings.theme)
            if store.settings.look == .custom {
                ColorPicker("Background", selection: colorBinding(\.background), supportsOpacity: false)
                    .help("Fills the band behind the stories.")
                ColorPicker("Text", selection: colorBinding(\.text), supportsOpacity: false)
                    .help("Draws headlines, outlet names, and rules.")
                ColorPicker("Major stories", selection: colorBinding(\.accent), supportsOpacity: false)
                    .help("Marks major stories and fills the line that counts down to the next page.")
            }
            LabeledContent("Next page every") {
                Slider(value: $store.settings.rotationSeconds, in: 10...120, step: 5)
                Text("\(Int(store.settings.rotationSeconds)) s").monospacedDigit().frame(
                    width: 60, alignment: .trailing)
            }
            .help("How long each page of top stories stays up before the next. Hovering holds the page.")
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
                            .help("The tag shown before this follow's headlines. A headline must contain it to show.")
                        TextField("Search", text: $store.settings.follows[index].query)
                            .help("The Google News search. Put a phrase in quotes for an exact match.")
                        Button {
                            store.settings.follows.remove(at: index)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("Stop following this.")
                    }
                    .labelsHidden()
                }
                Button("Add Follow") {
                    store.settings.follows.append(Follow(name: "", query: ""))
                }
                .help("Follow a team, person, or subject. Its newest stories join the ticker.")
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
                                .help("The outlet name shown with this feed's stories.")
                            TextField("https://example.com/feed.xml", text: $store.settings.feeds[index].url)
                                .help("The feed's RSS or Atom address.")
                            Button {
                                store.settings.feeds.remove(at: index)
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                            .help("Stop reading this feed.")
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
                .help("Add any RSS or Atom feed, such as one you curate in another app.")
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
                .help("Send a notification when a story turns major. Clicking it opens the story.")
            Stepper(value: $store.settings.alerts.minOutlets, in: 2...15) {
                LabeledContent("Major at", value: "\(store.settings.alerts.minOutlets) outlets")
            }
            .help("How many separate outlets must carry a story to count as major. Less topics need twice this.")
            Stepper(value: $store.settings.alerts.dailyCap, in: 1...20) {
                LabeledContent("At most", value: "\(store.settings.alerts.dailyCap) a day")
            }
            .help("The most alerts Crier sends in one day. Majors past the cap still get their red dot.")
            Picker("Quiet from", selection: $store.settings.alerts.quietStart) {
                ForEach(0..<24, id: \.self) { hour in
                    Text(hourText(hour)).tag(hour)
                }
            }
            .help("No alerts from this hour. Set both hours the same to alert around the clock.")
            Picker("Quiet until", selection: $store.settings.alerts.quietEnd) {
                ForEach(0..<24, id: \.self) { hour in
                    Text(hourText(hour)).tag(hour)
                }
            }
            .help("Alerts start again at this hour.")
            Stepper(value: $store.settings.alerts.maxAgeHours, in: 1...24, step: 1) {
                LabeledContent("Skip stories older than", value: "\(Int(store.settings.alerts.maxAgeHours)) h")
            }
            .help("A story that first broke longer ago than this never alerts, however big it grows.")
            Text("A story is major when that many separate outlets carry it. Majors get a red dot in the ticker.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }

    // emergencyPage sets which emergencies interrupt, the reader's area, and how loudly.
    private var emergencyPage: some View {
        Form {
            Picker("Emergency mode", selection: mode) {
                ForEach(EmergencyMode.choices(national: AppDelegate.national), id: \.self) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .help("Local warnings come from the National Weather Service for your area, in the United States only.")
            if store.settings.emergency.mode != .off {
                TextField("US ZIP code", text: $store.settings.emergency.zip, prompt: Text("This Mac's location"))
                    .help(
                        "Leave it empty to use this Mac's location. A ZIP code is checked at its center, so a "
                            + "warning that covers your home but not the center of your ZIP code may not show.")
                LabeledContent("Area", value: areaText)
                if locator.water {
                    FailureNote(
                        reason: "This spot is over water, so land warnings may miss it. Type a US ZIP code on land "
                            + "nearby.")
                }
                Picker("Sound and flash for", selection: $store.settings.emergency.sensitivity) {
                    ForEach(Sensitivity.allCases, id: \.self) { sensitivity in
                        Text(sensitivity.title).tag(sensitivity)
                    }
                }
                .help("Every other watch and warning for your area shows as the quiet orange line.")
                Toggle("Play the emergency sound", isOn: $store.settings.emergency.sound)
                    .help(
                        "Crier plays its own sound for the top tier, even when notification sounds are off. A muted "
                            + "Mac plays nothing.")
                HStack {
                    Picker("Sound", selection: $store.settings.emergency.soundName) {
                        ForEach(Siren.sounds, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                    Button("Preview") {
                        siren.preview()
                    }
                    .help("Play the sound once.")
                }
                .disabled(!store.settings.emergency.sound)
                Toggle("Flash the ticker", isOn: $store.settings.emergency.flashing)
                    .help("Three slow flashes, then steady red. Never when Reduce Motion is on.")
                LabeledContent("Last good check", value: checkedText)
                if let failure = feed.failure {
                    FailureNote(reason: failure)
                }
                LabeledContent("In force", value: siren.pinned ?? "Nothing")
                HStack(alignment: .firstTextBaseline) {
                    Text(feed.status(place: locator.place, problem: locator.problem))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button("Test Emergency Mode") {
                        siren.test()
                    }
                    .disabled(siren.testing)
                    .help("Show the red ticker, flash it, and play the sound, the way a real warning would.")
                }
            }
            Text(footerText)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }

    // mode is the emergency mode as the picker shows it. Builds without the national tier show a stored national
    // mode as local, the way they run it.
    private var mode: Binding<EmergencyMode> {
        Binding(
            get: { store.settings.emergency.mode.effective(national: AppDelegate.national) },
            set: { store.settings.emergency.mode = $0 })
    }

    // footerText explains what interrupts, what Crier cannot catch, and where the location goes.
    private var footerText: String {
        var text =
            "Life-safety warnings for your area, such as a tornado warning, turn the ticker red, flash it, and "
            + "play a sound, even in quiet hours. Watches and ordinary warnings, such as a flood watch, show "
            + "as a quiet orange line with no sound. Advisories and statements never show."
        if AppDelegate.national {
            text +=
                " National breaking news far bigger than major turns the ticker red without a sound, and only "
                + "wars, declared national emergencies, martial law, and nuclear attacks sound."
        }
        return text
            + "\n\nNot every alert a phone gets reaches Crier, and Crier checks only while this Mac is awake and "
            + "online. Crier sends your approximate location to the National Weather Service to ask for warnings "
            + "where you are. A typed ZIP code goes to Apple to find its center."
    }

    // areaText names the area warnings are checked for, or why there is none.
    private var areaText: String {
        if let problem = locator.problem {
            return problem
        }
        if feed.outside {
            return EmergencyFeed.outsideText
        }
        return locator.place ?? "Finding your area…"
    }

    // checkedText says when the Weather Service last answered.
    private var checkedText: String {
        feed.good?.formatted(date: .omitted, time: .shortened) ?? "Not yet"
    }

    // generalPage holds login, the refresh interval, and feed health.
    private var generalPage: some View {
        Form {
            Toggle(
                "Open at login",
                isOn: Binding(get: { loginItem.isEnabled }, set: { loginItem.setEnabled($0) })
            )
            .help("Start Crier when you log in to this Mac.")
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
            .help("How often Crier reads every feed.")
            LabeledContent("Last read", value: news.updated?.formatted(date: .omitted, time: .shortened) ?? "Not yet")
            LabeledContent("Headlines", value: "\(news.headlines.count)")
            if !news.failures.isEmpty {
                LabeledContent("Failed feeds", value: failedNames)
                    .help("The Sources and Feeds tabs explain each failure.")
            }
            HStack {
                Button("Refresh Now") {
                    Task { await news.refresh() }
                }
                .disabled(news.refreshing)
                .help("Read every feed now.")
                Spacer()
                Button("Restore Defaults") {
                    store.reset()
                }
                .help("Put every setting back the way Crier first came. Follows and your own feeds are cleared.")
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
        .help("Reads \(source.url.absoluteString)")
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

    // interestBinding sets how much of one topic to show.
    private func interestBinding(_ topic: Topic) -> Binding<Interest> {
        Binding(
            get: { store.settings.level(topic) },
            set: { store.settings.interest[topic] = $0 }
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
