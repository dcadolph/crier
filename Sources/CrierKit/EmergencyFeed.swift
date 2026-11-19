import Foundation
import Observation

// Spot is the reader's place, rounded to three decimals, about a city block, before it leaves the Mac.
public struct Spot: Codable, Sendable, Hashable {
    // latitude is degrees north.
    public let latitude: Double
    // longitude is degrees east, negative in the Americas.
    public let longitude: Double

    // init rounds a place to three decimals.
    public init(latitude: Double, longitude: Double) {
        self.latitude = (latitude * 1000).rounded() / 1000
        self.longitude = (longitude * 1000).rounded() / 1000
    }

    // point is the place as the Weather Service reads it, such as "30.267,-97.743".
    public var point: String {
        "\(latitude),\(longitude)"
    }

    // meters returns the distance to another spot along the Earth's surface.
    public func meters(to other: Spot) -> Double {
        let radius = 6_371_000.0
        let lat1 = latitude * .pi / 180
        let lat2 = other.latitude * .pi / 180
        let dLat = lat2 - lat1
        let dLon = (other.longitude - longitude) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * radius * atan2(sqrt(a), sqrt(1 - a))
    }
}

// EmergencyFeed polls the Weather Service for life-safety warnings at the reader's place and keeps the ones in
// force now. It checks only while running, so a stopped feed never reads, fills, or rings.
@MainActor
@Observable
public final class EmergencyFeed {
    // alerts are the urgent warnings in force at the spot, most dangerous first.
    public private(set) var alerts: [WeatherAlert] = []
    // notices are the watches and ordinary warnings in force at the spot, most dangerous first. They never ring.
    public private(set) var notices: [WeatherAlert] = []
    // failure says in plain words why the last check failed, or nil when it worked.
    public private(set) var failure: String?
    // checked is when the last check finished, whether or not it worked.
    public private(set) var checked: Date?
    // good is when the last check that worked finished.
    public private(set) var good: Date?
    // outside reports that the Weather Service refused the spot as outside the area it covers. Nothing is checked
    // again until the spot changes.
    public private(set) var outside = false
    // running reports whether the feed is between start and stop. Checks do nothing while it is false.
    public internal(set) var running = false
    // spot is the reader's place. Nil means no place is known yet, so nothing is checked. A new place clears the
    // warnings and the out of coverage mark until the next check, but keeps the record of what already rang, so a
    // warning heard before a move never rings again.
    public var spot: Spot? {
        didSet {
            if spot != oldValue {
                alerts = []
                notices = []
                outside = false
            }
        }
    }
    // sensitivity picks which warnings sound. The rest of the watches and warnings become notices.
    public var sensitivity = Sensitivity.phone
    // onRing runs with the warnings that just arrived, so the app can sound and flash once per warning. An update
    // to a warning that already rang does not ring again.
    @ObservationIgnored public var onRing: (([WeatherAlert]) -> Void)?

    // fetch reads the Weather Service.
    @ObservationIgnored private let fetch: Fetch
    // heard holds every alert identifier that already rang, with the identifiers those alerts updated.
    @ObservationIgnored private var heard: Set<String> = []
    // loop is the timer task.
    @ObservationIgnored private var loop: Task<Void, Never>?

    // interval is how often the Weather Service is checked.
    public static let interval: TimeInterval = 120
    // retry is how soon the Weather Service is checked again after a failed check.
    public static let retry: TimeInterval = 20
    // settle is how long after the Mac wakes the Weather Service is checked, so the network can come back first.
    public static let settle: TimeInterval = 10
    // outsideText says why nothing is checked outside the area the Weather Service covers.
    public static let outsideText = "The National Weather Service covers only the United States."
    // userAgent names the app and its repo, as the Weather Service asks of every client.
    public nonisolated static let userAgent = "Crier (github.com/dcadolph/crier)"

    // init builds the feed. fetch defaults to a plain HTTPS read of the Weather Service.
    public init(spot: Spot? = nil, fetch: @escaping Fetch = EmergencyFeed.download) {
        self.spot = spot
        self.fetch = fetch
    }

    // url is the Weather Service address for the warnings in force at a spot.
    public nonisolated static func url(for spot: Spot) -> URL {
        var parts = URLComponents(string: "https://api.weather.gov/alerts/active")!
        parts.queryItems = [URLQueryItem(name: "point", value: spot.point)]
        return parts.url!
    }

    // pointsURL is the Weather Service address that describes a spot, such as its county and forecast office.
    public nonisolated static func pointsURL(for spot: Spot) -> URL {
        URL(string: "https://api.weather.gov/points/\(spot.point)")!
    }

    // overWater reports whether a Weather Service description of a spot names no county, as for a spot over a
    // lake, a bay, or the sea, where land warnings may not reach.
    public nonisolated static func overWater(_ data: Data) throws -> Bool {
        let point = try JSONDecoder().decode(Point.self, from: data)
        return (point.properties.county ?? "").isEmpty
    }

    // start checks now and then on the interval until stop.
    public func start() {
        running = true
        run(after: 0)
    }

    // wake checks again shortly after the Mac wakes, when the last check may be long out of date.
    public func wake() {
        guard running else {
            return
        }
        run(after: Self.settle)
    }

    // stop ends the timer and clears the warnings, since nothing keeps them current any more. A check still in
    // flight changes nothing when it returns.
    public func stop() {
        running = false
        loop?.cancel()
        loop = nil
        alerts = []
        notices = []
    }

    // run replaces the timer with one that waits for delay seconds, then checks on the interval, or sooner after a
    // failed check.
    private func run(after delay: TimeInterval) {
        loop?.cancel()
        loop = Task { [weak self] in
            if delay > 0 {
                try? await Task.sleep(for: .seconds(delay))
            }
            while !Task.isCancelled {
                await self?.check()
                try? await Task.sleep(for: .seconds(self?.pause ?? Self.interval))
            }
        }
    }

    // pause is how long the timer waits before the next check: the interval, or the short retry after a failure.
    var pause: TimeInterval {
        failure == nil ? Self.interval : Self.retry
    }

    // check reads the warnings and notices at the spot and rings for the new warnings. A failed read keeps the
    // warnings and notices already known until they end, so a network blip never clears one still in force. A
    // refusal with status 400 marks the spot as outside the Weather Service's area. Nothing changes when the feed
    // stops or the spot moves while the read is in flight.
    public func check(now: Date = Date()) async {
        guard running, !outside, let spot else {
            return
        }
        let read: Result<[WeatherAlert], Error>
        do {
            read = .success(try WeatherAlerts.decode(try await fetch(Self.url(for: spot))))
        } catch {
            read = .failure(error)
        }
        guard running, spot == self.spot else {
            return
        }
        switch read {
        case .success(let all):
            alerts = Emergency.active(all, now: now, sensitivity: sensitivity, heard: heard)
            notices = Emergency.notices(all, now: now, sensitivity: sensitivity, heard: heard)
            failure = nil
            good = now
        case .failure(FeedError.status(400)):
            alerts = []
            notices = []
            failure = nil
            outside = true
        case .failure(let error):
            let known = alerts + notices
            alerts = Emergency.active(known, now: now, sensitivity: sensitivity, heard: heard)
            notices = Emergency.notices(known, now: now, sensitivity: sensitivity, heard: heard)
            failure = News.reason(error)
        }
        checked = now
        let (ring, heard) = Emergency.ring(alerts, heard: heard)
        self.heard = heard
        if !ring.isEmpty {
            onRing?(ring)
        }
    }

    // status says in one line what the feed watches, or why it watches nothing: the reader's place, the problem
    // finding it, no place yet, a place outside the Weather Service's area, or checks that keep failing.
    public func status(place: String?, problem: String?) -> String {
        if let problem {
            return "Not watching for warnings. \(problem)"
        }
        if outside {
            return "Not watching for warnings. \(Self.outsideText)"
        }
        guard spot != nil else {
            return "Not watching for warnings yet. Finding your area…"
        }
        let area = place ?? "your area"
        guard failure != nil else {
            return "Watching \(area) for warnings."
        }
        guard let good else {
            return "Warnings for \(area) could not be checked yet. Crier keeps trying."
        }
        return "Warnings for \(area) could not be checked since \(good.formatted(date: .omitted, time: .shortened)). "
            + "Crier keeps trying."
    }

    // download reads a Weather Service address with the user agent and GeoJSON type it asks for, and refuses any
    // status other than 200.
    public nonisolated static func download(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/geo+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw FeedError.status(http.statusCode)
        }
        return data
    }
}

// Point is the part of the Weather Service's description of a spot that Crier reads.
private struct Point: Decodable {
    // Properties holds the description's fields.
    struct Properties: Decodable {
        // county is the address of the spot's county zone, or nil over water.
        let county: String?
    }

    // properties holds the description's fields.
    let properties: Properties
}
