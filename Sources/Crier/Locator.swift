import CoreLocation
import Observation

import CrierKit

// Locator finds the reader's spot for emergency warnings: from the ZIP code in settings, or from the Mac's location
// when no ZIP code is set. The spot stays on the Mac except for the rounded point sent to the Weather Service.
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

    // init builds a locator that reports to the delegate methods below.
    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    // locate finds the spot for a ZIP code, or for the Mac's location when the ZIP code is empty.
    func locate(zip raw: String) {
        zip = raw.trimmingCharacters(in: .whitespaces)
        geocoder.cancelGeocode()
        if zip.isEmpty {
            locateMac()
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

    // locationManager keeps the Mac's location as the spot.
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else {
            return
        }
        let found = Spot(latitude: last.coordinate.latitude, longitude: last.coordinate.longitude)
        Task { @MainActor in
            if self.zip.isEmpty {
                self.report(found, place: "This Mac's location", problem: nil)
            }
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
