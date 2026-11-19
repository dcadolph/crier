import AppKit
import CoreLocation
import Observation

import CrierKit

// Locator finds the reader's spot for emergency warnings: from the ZIP code in settings, or from the Mac's location
// when no ZIP code is set. It reads the Mac's location again on an interval and after the Mac wakes, so the spot
// follows a laptop that moves. A typed ZIP code goes to Apple's geocoder to find its center, and the rounded spot
// goes to the Weather Service. It does nothing between stop and the next locate, so with emergency mode off no
// location is read or sent.
@MainActor
@Observable
final class Locator: NSObject, CLLocationManagerDelegate {
    // spot is the reader's place, or nil until one is found.
    private(set) var spot: Spot?
    // place names the spot in plain words, such as "Austin, TX".
    private(set) var place: String?
    // problem says in plain words why no spot is known, or nil.
    private(set) var problem: String?
    // water reports that the Weather Service names no county at the spot, as over a lake, a bay, or the sea.
    private(set) var water = false
    // onSpot runs whenever the spot changes.
    @ObservationIgnored var onSpot: ((Spot?) -> Void)?

    // manager reads the Mac's location.
    @ObservationIgnored private let manager = CLLocationManager()
    // geocoder turns a ZIP code into a place.
    @ObservationIgnored private let geocoder = CLGeocoder()
    // zip is the ZIP code last asked for, empty for the Mac's location.
    @ObservationIgnored private var zip = ""
    // started reports whether locate ran since the last stop. Location callbacks do nothing while it is false.
    @ObservationIgnored private var started = false
    // refreshing reads the Mac's location again on the interval while no ZIP code is set.
    @ObservationIgnored private var refreshing: Task<Void, Never>?
    // retrying looks the ZIP code up again after a failed lookup.
    @ObservationIgnored private var retrying: Task<Void, Never>?
    // surveying asks the Weather Service whether the spot is over water.
    @ObservationIgnored private var surveying: Task<Void, Never>?

    // every is how often the Mac's location is read again while no ZIP code is set.
    static let every = Duration.seconds(30 * 60)
    // moved is how far, in meters, the Mac must move before its new location replaces the spot. Smaller changes
    // are the location's own wobble, and replacing the spot for them would clear the warnings until the next check.
    static let moved = 1000.0
    // firstRetry is how long after a failed ZIP code lookup Crier tries again. Each failure doubles the wait.
    static let firstRetry = Duration.seconds(30)
    // lastRetry is the longest wait between ZIP code lookups.
    static let lastRetry = Duration.seconds(30 * 60)
    // savedKey is the user defaults key holding the last spot found for each ZIP code.
    static let savedKey = "emergencySpots"

    // Saved is a spot found for a ZIP code, kept so it is ready at once on the next launch.
    struct Saved: Codable {
        // spot is the ZIP code's center.
        let spot: Spot
        // place names the spot in plain words.
        let place: String
    }

    // init builds a locator that reports to the delegate methods below.
    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(woke), name: NSWorkspace.didWakeNotification, object: nil)
    }

    // locate finds the spot for a ZIP code, or for the Mac's location when the ZIP code is empty. A ZIP code found
    // before is used at once while the fresh lookup runs.
    func locate(zip raw: String) {
        stop()
        started = true
        zip = raw.trimmingCharacters(in: .whitespaces)
        if zip.isEmpty {
            locateMac()
            refreshing = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: Self.every)
                    guard !Task.isCancelled else {
                        return
                    }
                    self?.locateMac()
                }
            }
            return
        }
        guard zip.count == 5, zip.allSatisfy(\.isNumber) else {
            report(nil, place: nil, problem: "Type a five-digit US ZIP code.")
            return
        }
        let saved = Self.saved()[zip]
        report(saved?.spot, place: saved?.place, problem: nil)
        lookup(zip, wait: Self.firstRetry)
    }

    // stop ends the interval reads, any ZIP code lookup and its retries, and the water check, as when emergency
    // mode turns off. Location callbacks do nothing after it.
    func stop() {
        started = false
        refreshing?.cancel()
        refreshing = nil
        retrying?.cancel()
        retrying = nil
        surveying?.cancel()
        surveying = nil
        geocoder.cancelGeocode()
    }

    // lookup asks Apple's geocoder for a ZIP code's center. While no spot is known, a failed lookup tries again
    // after wait, and each later failure doubles the wait up to lastRetry.
    private func lookup(_ asked: String, wait: Duration) {
        geocoder.geocodeAddressString("\(asked), United States") { [weak self] marks, error in
            let mark = marks?.first
            let found = mark?.location.map {
                Spot(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude)
            }
            let place = [mark?.locality, mark?.administrativeArea].compactMap(\.self).joined(separator: ", ")
            let code = (error as? CLError)?.code
            let canceled = code == .geocodeCanceled
            let none = error == nil || code == .geocodeFoundNoResult || code == .geocodeFoundPartialResult
            Task { @MainActor in
                guard let self, self.started, self.zip == asked, !canceled else {
                    return
                }
                if let found {
                    let name = place.isEmpty ? "ZIP \(asked)" : place
                    Self.save(Saved(spot: found, place: name), zip: asked)
                    self.report(found, place: name, problem: nil)
                } else if none {
                    self.report(nil, place: nil, problem: "No place has that ZIP code.")
                } else if self.spot == nil {
                    self.report(nil, place: nil, problem: "Crier could not look up that ZIP code. It tries again soon.")
                    self.retry(asked, wait: wait)
                }
            }
        }
    }

    // retry looks the ZIP code up again after wait, unless a spot was found or the ZIP code changed meanwhile.
    private func retry(_ asked: String, wait: Duration) {
        retrying?.cancel()
        retrying = Task { [weak self] in
            try? await Task.sleep(for: wait)
            guard !Task.isCancelled, let self, self.started, self.zip == asked, self.spot == nil else {
                return
            }
            self.lookup(asked, wait: min(wait * 2, Self.lastRetry))
        }
    }

    // woke reads the Mac's location again after sleep, since a laptop often wakes somewhere new, and looks a ZIP
    // code up again soon when its lookup was still failing before sleep.
    @objc private func woke() {
        guard started else {
            return
        }
        if refreshing != nil {
            locateMac()
        } else if retrying != nil, spot == nil {
            retry(zip, wait: Self.firstRetry)
        }
    }

    // locateMac asks for the Mac's location, first asking permission when the reader has not answered yet.
    private func locateMac() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorized, .authorizedAlways:
            manager.requestLocation()
        default:
            report(
                nil, place: nil,
                problem: "Location is off for Crier. Type a US ZIP code, or allow location in System Settings.")
        }
    }

    // report keeps the result and tells the listener when the spot changed.
    private func report(_ found: Spot?, place: String?, problem: String?) {
        self.place = place
        self.problem = problem
        guard found != spot else {
            return
        }
        spot = found
        survey(found)
        onSpot?(found)
    }

    // survey asks the Weather Service once per spot whether it names a county there, so Settings can say when the
    // spot is over water and land warnings may miss it.
    private func survey(_ spot: Spot?) {
        surveying?.cancel()
        water = false
        guard let spot else {
            return
        }
        surveying = Task { [weak self] in
            guard let data = try? await EmergencyFeed.download(EmergencyFeed.pointsURL(for: spot)),
                let water = try? EmergencyFeed.overWater(data), !Task.isCancelled, let self, self.spot == spot
            else {
                return
            }
            self.water = water
        }
    }

    // saved reads the last spot found for each ZIP code.
    private static func saved() -> [String: Saved] {
        guard let data = UserDefaults.standard.data(forKey: savedKey),
            let saved = try? JSONDecoder().decode([String: Saved].self, from: data)
        else {
            return [:]
        }
        return saved
    }

    // save keeps the spot found for a ZIP code.
    private static func save(_ found: Saved, zip: String) {
        var all = saved()
        all[zip] = found
        if let data = try? JSONEncoder().encode(all) {
            UserDefaults.standard.set(data, forKey: savedKey)
        }
    }

    // locationManagerDidChangeAuthorization reads the location once the reader answers the permission prompt. It
    // also runs when the manager is created, so it does nothing until locate runs.
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            if self.started, self.zip.isEmpty {
                self.locateMac()
            }
        }
    }

    // locationManager keeps the Mac's location as the spot, unless it is within the wobble of the spot already
    // known.
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else {
            return
        }
        let found = Spot(latitude: last.coordinate.latitude, longitude: last.coordinate.longitude)
        Task { @MainActor in
            guard self.started, self.zip.isEmpty else {
                return
            }
            let near = self.spot.map { $0.meters(to: found) < Self.moved } ?? false
            self.report(near ? self.spot : found, place: "This Mac's location", problem: nil)
        }
    }

    // locationManager reports a failed location read, keeping any spot already known.
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            guard self.started, self.zip.isEmpty, self.spot == nil else {
                return
            }
            self.problem = "Crier could not read this Mac's location. Type a US ZIP code instead."
        }
    }
}
