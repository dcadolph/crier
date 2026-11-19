import Foundation
import Testing

@testable import CrierKit

// EmergencyFeedRecoveryTests covers the feed's gates and dead states: checks before start and after stop, a spot
// outside the Weather Service's area, the status line, the spot description over water, and the mode choices.
@MainActor
struct EmergencyFeedRecoveryTests {
    // Answer holds the next response, a failure status, or a fetch held until it is opened.
    final class Answer: @unchecked Sendable {
        // data is the response.
        var data: Data?
        // status is a status code to refuse with instead of answering.
        var status: Int?
        // held keeps the fetch waiting while it is true.
        var held = false
        // urls are the addresses read.
        var urls: [URL] = []
    }

    // spot is the place every case checks first.
    private let spot = Spot(latitude: 37, longitude: -122)

    // feed builds a feed that answers from answer.
    private func feed(_ answer: Answer) -> EmergencyFeed {
        EmergencyFeed(spot: spot) { url in
            answer.urls.append(url)
            while answer.held {
                try await Task.sleep(for: .milliseconds(5))
            }
            if let status = answer.status {
                throw FeedError.status(status)
            }
            guard let data = answer.data else {
                throw URLError(.notConnectedToInternet)
            }
            return data
        }
    }

    // tornado returns the recorded tornado warning that went to phones.
    private func tornado() throws -> WeatherAlert {
        try #require(
            try WeatherAlerts.decode(try recorded("weather-alerts")).first { $0.messageType == "Alert" && $0.phones })
    }

    // checkBeforeStartDoesNothing never reads or rings before start, as when the spot arrives with the mode off.
    @Test func checkBeforeStartDoesNothing() async throws {
        let answer = Answer()
        answer.data = try recorded("weather-alerts")
        let feed = feed(answer)
        var rung = 0
        feed.onRing = { _ in rung += 1 }
        await feed.check(now: try tornado().sent)
        #expect(answer.urls.isEmpty)
        #expect(feed.alerts.isEmpty)
        #expect(rung == 0)
    }

    // checkAfterStopDoesNothing never reads or rings once the feed stops.
    @Test func checkAfterStopDoesNothing() async throws {
        let answer = Answer()
        answer.data = try recorded("weather-alerts")
        let feed = feed(answer)
        var rung = 0
        feed.onRing = { _ in rung += 1 }
        feed.running = true
        feed.stop()
        await feed.check(now: try tornado().sent)
        #expect(answer.urls.isEmpty)
        #expect(rung == 0)
    }

    // checkInFlightAtStopChangesNothing drops a read that was in flight when the feed stopped, so it neither fills
    // the warnings nor rings.
    @Test func checkInFlightAtStopChangesNothing() async throws {
        let answer = Answer()
        answer.data = try recorded("weather-alerts")
        answer.held = true
        let feed = feed(answer)
        var rung = 0
        feed.onRing = { _ in rung += 1 }
        feed.running = true
        let sent = try tornado().sent
        let inFlight = Task { await feed.check(now: sent) }
        while answer.urls.isEmpty {
            try await Task.sleep(for: .milliseconds(5))
        }
        feed.stop()
        answer.held = false
        await inFlight.value
        #expect(feed.alerts.isEmpty)
        #expect(feed.checked == nil)
        #expect(rung == 0)
    }

    // outsideStopsAskingUntilMove marks a spot the Weather Service refuses with status 400 as outside its area,
    // asks no more there, and asks again once the spot changes.
    @Test func outsideStopsAskingUntilMove() async throws {
        let answer = Answer()
        answer.status = 400
        let feed = feed(answer)
        feed.running = true
        await feed.check()
        #expect(feed.outside)
        #expect(feed.failure == nil)
        #expect(feed.status(place: "London", problem: nil).hasSuffix(EmergencyFeed.outsideText))
        await feed.check()
        #expect(answer.urls.count == 1)
        answer.status = nil
        answer.data = try recorded("weather-none")
        feed.spot = Spot(latitude: 30, longitude: -97)
        #expect(!feed.outside)
        await feed.check()
        #expect(answer.urls.count == 2)
        #expect(!feed.outside)
        #expect(feed.good != nil)
    }

    // otherStatusIsFailure keeps a refusal other than 400 as a failed check that is tried again after the short
    // retry, and the next good check goes back to the full interval.
    @Test func otherStatusIsFailure() async throws {
        let answer = Answer()
        answer.status = 503
        let feed = feed(answer)
        feed.running = true
        await feed.check()
        #expect(!feed.outside)
        #expect(feed.failure != nil)
        #expect(feed.good == nil)
        #expect(feed.checked != nil)
        #expect(feed.pause == EmergencyFeed.retry)
        answer.status = nil
        answer.data = try recorded("weather-none")
        await feed.check()
        #expect(feed.pause == EmergencyFeed.interval)
    }

    // statusNamesEachState says what the feed watches, or why it watches nothing, in each state.
    @Test func statusNamesEachState() async throws {
        let answer = Answer()
        answer.data = try recorded("weather-none")
        let feed = feed(answer)
        feed.running = true
        #expect(
            feed.status(place: nil, problem: "Location is off for Crier.")
                == "Not watching for warnings. Location is off for Crier.")
        await feed.check()
        #expect(feed.status(place: "Austin, TX", problem: nil) == "Watching Austin, TX for warnings.")
        answer.data = nil
        await feed.check()
        #expect(
            feed.status(place: "Austin, TX", problem: nil).hasPrefix("Warnings for Austin, TX could not be checked"))
        feed.spot = nil
        #expect(feed.status(place: nil, problem: nil) == "Not watching for warnings yet. Finding your area…")
    }

    // overWaterReadsCounty reports water when the spot's description names no county, and land when it does.
    @Test func overWaterReadsCounty() throws {
        let land = Data(#"{"properties":{"county":"https://api.weather.gov/zones/county/TXC453"}}"#.utf8)
        let water = Data(
            #"{"properties":{"county":null,"forecastZone":"https://api.weather.gov/zones/forecast/PZZ535"}}"#.utf8)
        let empty = Data(#"{"properties":{}}"#.utf8)
        #expect(try !EmergencyFeed.overWater(land))
        #expect(try EmergencyFeed.overWater(water))
        #expect(try EmergencyFeed.overWater(empty))
        #expect(
            EmergencyFeed.pointsURL(for: Spot(latitude: 30.2672, longitude: -97.7431)).absoluteString
                == "https://api.weather.gov/points/30.267,-97.743")
    }

    // modeChoicesHideNational leaves the national mode out of the choices and runs it as local unless the build
    // offers it.
    @Test func modeChoicesHideNational() {
        #expect(EmergencyMode.choices(national: false) == [.off, .local])
        #expect(EmergencyMode.choices(national: true) == [.off, .local, .localAndNational])
        #expect(EmergencyMode.localAndNational.effective(national: false) == .local)
        #expect(EmergencyMode.localAndNational.effective(national: true) == .localAndNational)
        #expect(EmergencyMode.off.effective(national: false) == .off)
    }
}
