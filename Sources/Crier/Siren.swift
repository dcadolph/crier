import AppKit
import Observation

import CrierKit

// Siren holds the emergency in force and interrupts for it: an orange pinned line for a watch or an ordinary
// warning, the red ticker for the red tier and up, and flashing, the emergency sound, and a notification for the
// top tier. Emergencies break through quiet hours.
@MainActor
@Observable
final class Siren {
    // warnings are the life-safety warnings in force at the reader's spot, newest first.
    private(set) var warnings: [WeatherAlert] = []
    // notices are the watches and ordinary warnings in force at the reader's spot, newest first. They never sound.
    private(set) var notices: [WeatherAlert] = []
    // stories are the national stories past the red tier, loudest first.
    private(set) var stories: [(headline: Headline, tier: Tier)] = []
    // rings counts top tier interruptions, so every ticker flashes together when it changes.
    private(set) var rings = 0
    // acknowledged reports whether the reader clicked the latest interruption, which stops its sound.
    private(set) var acknowledged = true
    // testing reports whether a test emergency is showing.
    private(set) var testing = false
    // spot is the reader's place, used for the warning page link.
    var spot: Spot?

    // store holds the live settings.
    @ObservationIgnored private let store: SettingsStore
    // notifier posts the emergency notification.
    @ObservationIgnored private let notifier: Notifier
    // rung holds the keywords of national stories that already sounded.
    @ObservationIgnored private var rung: [Set<String>] = []
    // sounding repeats the emergency sound until it runs out or the reader clicks.
    @ObservationIgnored private var sounding: Task<Void, Never>?
    // test ends the test emergency.
    @ObservationIgnored private var testEnd: Task<Void, Never>?
    // posted maps each emergency notification still on screen to the alert identifiers of its warning, so it can
    // be withdrawn when that warning ends.
    @ObservationIgnored private var posted: [String: Set<String>] = [:]

    // sounds are the names of the system sounds the reader can pick, from the system's sounds and the reader's
    // own, sorted and without repeats.
    static let sounds: [String] = {
        let folders = [
            URL(filePath: "/System/Library/Sounds"),
            FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Sounds"),
        ]
        let kinds: Set<String> = ["aiff", "aif", "wav", "caf", "m4a"]
        let names = folders.flatMap { folder in
            let files =
                (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            return files.filter { kinds.contains($0.pathExtension.lowercased()) }
                .map { $0.deletingPathExtension().lastPathComponent }
        }
        return Set(names + [EmergencyRules.defaultSound]).sorted()
    }()
    // repeats is how many times the sound plays when nobody clicks.
    static let repeats = 5
    // gap is the time between plays of the sound.
    static let gap = Duration.seconds(3)
    // testLength is how long a test emergency stays up.
    static let testLength = Duration.seconds(12)

    // init builds a siren that posts through the notifier.
    init(store: SettingsStore, notifier: Notifier) {
        self.store = store
        self.notifier = notifier
    }

    // tier is the loudest emergency in force.
    var tier: Tier {
        if testing || !warnings.isEmpty {
            return .top
        }
        if let story = stories.first {
            return story.tier
        }
        return notices.isEmpty ? .none : .orange
    }

    // pinned is the line pinned in front of the ticker: the test, the newest warning, the loudest story, or the
    // newest notice.
    var pinned: String? {
        if testing {
            return store.settings.emergency.sound
                ? "TEST: A real warning looks like this and plays this sound until you click."
                : "TEST: A real warning looks like this. The emergency sound is off in Settings."
        }
        if let warning = warnings.first {
            return line(warning, loud: true)
        }
        if let story = stories.first {
            return story.headline.lead.title
        }
        return notices.first.map { line($0, loud: false) }
    }

    // link is the page that explains the pinned line: the forecast page for a warning or a notice, or the story.
    var link: URL? {
        if warnings.isEmpty, let story = stories.first {
            return story.headline.lead.link
        }
        guard !warnings.isEmpty || !notices.isEmpty, let spot else {
            return nil
        }
        return URL(string: "https://forecast.weather.gov/MapClick.php?lat=\(spot.latitude)&lon=\(spot.longitude)")
    }

    // notice takes the watches and ordinary warnings in force. They pin a quiet line and never ring.
    func notice(_ active: [WeatherAlert]) {
        notices = active
    }

    // warn takes the warnings in force, rings for the new ones, and withdraws the notifications of the ones that
    // ended.
    func warn(_ active: [WeatherAlert], new: [WeatherAlert]) {
        warnings = active
        withdraw(keeping: active)
        guard let newest = new.first else {
            if active.isEmpty {
                stopSound()
            }
            return
        }
        ring()
        notifier.postEmergency(
            id: newest.id, title: line(newest, loud: true),
            body: newest.instruction ?? newest.headline ?? newest.area, link: link)
        posted[newest.id] = Set([newest.id] + newest.references)
    }

    // withdraw takes down the notification of every warning no longer in force. An update to a warning keeps its
    // notification, since the update names the earlier alert in its references.
    private func withdraw(keeping active: [WeatherAlert]) {
        let live = Set(active.flatMap { [$0.id] + $0.references })
        let ended = posted.filter { $0.value.isDisjoint(with: live) }.map(\.key)
        guard !ended.isEmpty else {
            return
        }
        notifier.withdrawEmergency(ids: ended)
        for id in ended {
            posted[id] = nil
        }
    }

    // read takes the latest headlines and rings for a national top tier story that has not sounded yet. The first
    // read after launch turns the ticker red without sounding, since those stories were out before Crier started.
    func read(_ headlines: [Headline], first: Bool) {
        let rules = store.settings.emergency.national
        stories = Emergency.national(headlines, rules: rules, now: Date()).map { ($0.0, $0.1) }
        let loud = stories.filter { $0.tier == .top }.map(\.headline)
        let fresh = loud.filter { story in !rung.contains { Coverage.same($0, story.keywords) } }
        rung += fresh.map(\.keywords)
        guard !first, let story = fresh.first else {
            return
        }
        ring()
        notifier.postEmergency(
            id: story.id, title: story.lead.title,
            body: "\(story.lead.outlet) and \(story.outlets.count - 1) more outlets are reporting this.",
            link: story.lead.link)
    }

    // clear drops every emergency and withdraws their notifications, as when emergency mode is turned off.
    func clear() {
        withdraw(keeping: [])
        warnings = []
        notices = []
        stories = []
        endTest()
        stopSound()
    }

    // test shows a test emergency with flashing and sound, then takes it down.
    func test() {
        testing = true
        ring()
        testEnd?.cancel()
        testEnd = Task { [weak self] in
            try? await Task.sleep(for: Self.testLength)
            guard !Task.isCancelled else {
                return
            }
            self?.endTest()
        }
    }

    // click acknowledges the interruption, which stops the sound, or opens its page once acknowledged.
    func click() {
        if !acknowledged {
            stopSound()
            if testing {
                endTest()
            }
            return
        }
        if let link {
            NSWorkspace.shared.open(link)
        }
    }

    // ring flashes the tickers and plays the sound, as the settings allow.
    private func ring() {
        acknowledged = false
        rings += 1
        sounding?.cancel()
        guard store.settings.emergency.sound else {
            acknowledged = true
            return
        }
        sounding = Task { [weak self] in
            for _ in 0..<Self.repeats {
                guard !Task.isCancelled else {
                    return
                }
                self?.chosenSound()?.play()
                try? await Task.sleep(for: Self.gap)
            }
            self?.acknowledged = true
        }
    }

    // preview plays the chosen sound once, so the reader can hear it before an emergency does.
    func preview() {
        guard let sound = chosenSound() else {
            return
        }
        sound.stop()
        sound.play()
    }

    // chosenSound returns the sound picked in settings, or the default when that sound is gone.
    private func chosenSound() -> NSSound? {
        NSSound(named: store.settings.emergency.soundName) ?? NSSound(named: EmergencyRules.defaultSound)
    }

    // stopSound ends the sound and marks the interruption acknowledged.
    private func stopSound() {
        sounding?.cancel()
        sounding = nil
        acknowledged = true
    }

    // endTest takes the test emergency down.
    private func endTest() {
        testEnd?.cancel()
        testEnd = nil
        testing = false
    }

    // line writes an alert for the ticker, such as "TORNADO WARNING until 1:30 PM" when loud or "Flood Watch until
    // Thu 1:00 PM" when quiet. The day shows when the alert runs past today.
    private func line(_ alert: WeatherAlert, loud: Bool) -> String {
        let event = loud ? alert.event.uppercased() : alert.event
        guard let until = alert.until else {
            return event
        }
        let time =
            Calendar.current.isDateInToday(until)
            ? until.formatted(date: .omitted, time: .shortened)
            : until.formatted(.dateTime.weekday(.abbreviated).hour().minute())
        return "\(event) until \(time)"
    }
}
