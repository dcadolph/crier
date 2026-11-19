import AppKit
import Observation

import CrierKit

// Siren holds the emergency in force and interrupts for it: the red ticker for every tier, and flashing, the
// emergency sound, and a notification for the top tier. Emergencies break through quiet hours.
@MainActor
@Observable
final class Siren {
    // warnings are the life-safety warnings in force at the reader's spot, newest first.
    private(set) var warnings: [WeatherAlert] = []
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

    // sound is the system sound Crier plays for an emergency.
    static let sound = "Sosumi"
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
        return stories.first?.tier ?? .none
    }

    // pinned is the line pinned in front of the ticker: the newest warning, the loudest story, or the test.
    var pinned: String? {
        if testing {
            return "TEST: emergency mode is working. Click to stop the sound."
        }
        if let warning = warnings.first {
            return line(warning)
        }
        return stories.first?.headline.lead.title
    }

    // link is the page that explains the pinned line.
    var link: URL? {
        if !warnings.isEmpty, let spot {
            return URL(
                string: "https://forecast.weather.gov/MapClick.php?lat=\(spot.latitude)&lon=\(spot.longitude)")
        }
        return stories.first?.headline.lead.link
    }

    // warn takes the warnings in force and rings for the new ones.
    func warn(_ active: [WeatherAlert], new: [WeatherAlert]) {
        warnings = active
        guard let newest = new.first else {
            if active.isEmpty {
                stopSound()
            }
            return
        }
        ring()
        notifier.postEmergency(
            id: newest.id, title: line(newest), body: newest.instruction ?? newest.headline ?? newest.area, link: link)
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

    // clear drops every emergency, as when emergency mode is turned off.
    func clear() {
        warnings = []
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
                NSSound(named: Self.sound)?.play()
                try? await Task.sleep(for: Self.gap)
            }
            self?.acknowledged = true
        }
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

    // line writes a warning for the ticker, such as "TORNADO WARNING until 1:30 PM".
    private func line(_ warning: WeatherAlert) -> String {
        let event = warning.event.uppercased()
        guard let until = warning.until else {
            return event
        }
        return "\(event) until \(until.formatted(date: .omitted, time: .shortened))"
    }
}
