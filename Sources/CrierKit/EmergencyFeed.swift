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
}

// EmergencyFeed polls the Weather Service for life-safety warnings at the reader's place and keeps the ones in
// force now.
@MainActor
@Observable
public final class EmergencyFeed {
    // alerts are the urgent warnings in force at the spot, newest first.
    public private(set) var alerts: [WeatherAlert] = []
    // notices are the watches and ordinary warnings in force at the spot, newest first. They never ring.
    public private(set) var notices: [WeatherAlert] = []
    // failure says in plain words why the last check failed, or nil when it worked.
    public private(set) var failure: String?
    // checked is when the last check finished.
    public private(set) var checked: Date?
    // spot is the reader's place. Nil means no place is known yet, so nothing is checked.
    public var spot: Spot? {
        didSet {
            if spot != oldValue {
                alerts = []
                notices = []
                heard = []
            }
        }
    }
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

    // start checks now and then on the interval until stop.
    public func start() {
        loop?.cancel()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.check()
                try? await Task.sleep(for: .seconds(Self.interval))
            }
        }
    }

    // stop ends the timer and clears the warnings, since nothing keeps them current any more.
    public func stop() {
        loop?.cancel()
        loop = nil
        alerts = []
        notices = []
    }

    // check reads the warnings and notices at the spot and rings for the new warnings. A failed read keeps the
    // warnings and notices already known until they end, so a network blip never clears one still in force.
    public func check(now: Date = Date()) async {
        guard let spot else {
            return
        }
        do {
            let all = try WeatherAlerts.decode(try await fetch(Self.url(for: spot)))
            guard spot == self.spot else {
                return
            }
            alerts = Emergency.active(all, now: now)
            notices = Emergency.notices(all, now: now)
            failure = nil
        } catch {
            alerts = Emergency.active(alerts, now: now)
            notices = Emergency.notices(notices, now: now)
            failure = News.reason(error)
        }
        checked = now
        let (ring, heard) = Emergency.ring(alerts, heard: heard)
        self.heard = heard
        if !ring.isEmpty {
            onRing?(ring)
        }
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
