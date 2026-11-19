import AppKit
import CoreLocation
import Observation

import CrierKit

// Locator finds the reader's spot for emergency warnings: from the ZIP code in settings, or from the Mac's location
// when no ZIP code is set. It reads the Mac's location again on an interval and after the Mac wakes, so the spot
// follows a laptop that moves. The spot stays on the Mac except for the rounded point sent to the Weather Service.
@MainActor
@Observable
final class Locator: NSObject, CLLocationManagerDelegate {
    // spot is the reader's place, or nil until one is found.
    private(set) var spot: Spot?
    // place names the spot in plain words, such as "Austin, TX".
    private(set) var place: String?
    // problem says in plain words why no spot is known, or nil.
    private(set) var problem: String?
    // onSpot runs whenever the spot changes.
    @ObservationIgnored var onSpot: ((Spot?) -> Void)?

    // manager reads the Mac's location.
    @ObservationIgnored private let manager = CLLocationManager()
    // geocoder turns a ZIP code into a place.
    @ObservationIgnored private let geocoder = CLGeocoder()
    // zip is the ZIP code last asked for, empty for the Mac's location.
    @ObservationIgnored private var zip = ""
    // refreshing reads the Mac's location again on the interval while no ZIP code is set.
    @ObservationIgnored private var refreshing: Task<Void, Never>?

    // every is how often the Mac's location is read again while no ZIP code is set.
    static let every = Duration.seconds(30 * 60)
    // moved is how far, in meters, the Mac must move before its new location replaces the spot. Smaller changes
    // are the location's own wobble, and replacing the spot for them would clear the warnings until the next check.
    static let moved = 1000.0

    // init builds a locator that reports to the delegate methods below.
    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(woke), name: NSWorkspace.didWakeNotification, object: nil)
    }

    // locate finds the spot for a ZIP code, or for the Mac's location when the ZIP code is empty.
    func locate(zip raw: String) {
        zip = raw.trimmingCharacters(in: .whitespaces)
        stop()
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
            report(nil, place: nil, problem: "Type a five digit ZIP code.")
            return
        }
        let asked = zip
        geocoder.geocodeAddressString("\(asked), United States") { [weak self] marks, error in
            let mark = marks?.first
            let found = mark?.location.map {
                Spot(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude)
            }
            let place = [mark?.locality, mark?.administrativeArea].compactMap(\.self).joined(separator: ", ")
            let failed = error != nil
            Task { @MainActor in
                guard let self, self.zip == asked else {
                    return
                }
                if let found {
                    self.report(found, place: place.isEmpty ? "ZIP \(asked)" : place, problem: nil)
                } else {
                    self.report(
                        nil, place: nil,
                        problem: failed ? "Crier could not look up that ZIP code." : "No place has that ZIP code.")
                }
            }
        }
    }

    // stop ends the interval reads and any ZIP code lookup, as when emergency mode turns off.
    func stop() {
        refreshing?.cancel()
        refreshing = nil
        geocoder.cancelGeocode()
    }

    // woke reads the Mac's location again after sleep, since a laptop often wakes somewhere new.
    @objc private func woke() {
        if refreshing != nil {
            locateMac()
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
                nil, place: nil, problem: "Location is off for Crier. Type a ZIP code, or allow it in System Settings.")
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
        onSpot?(found)
    }

    // locationManagerDidChangeAuthorization reads the location once the reader answers the permission prompt.
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            if self.zip.isEmpty {
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
            guard self.zip.isEmpty else {
                return
            }
            let near = self.spot.map { $0.meters(to: found) < Self.moved } ?? false
            self.report(near ? self.spot : found, place: "This Mac's location", problem: nil)
        }
    }

    // locationManager reports a failed location read, keeping any spot already known.
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            guard self.zip.isEmpty, self.spot == nil else {
                return
            }
            self.problem = "Crier could not read this Mac's location. Type a ZIP code instead."
        }
    }
}
