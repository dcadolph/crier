import Foundation
import SwiftUI
import Testing

@testable import CrierKit

// SettingsTests covers forgiving decode, the feed list, and the band theme.
struct SettingsTests {
    // decode reads JSON into settings.
    private func decode(_ json: String) throws -> CrierKit.Settings {
        try JSONDecoder().decode(CrierKit.Settings.self, from: Data(json.utf8))
    }

    // emptyDecodesDefaults gives every default for an empty object.
    @Test func emptyDecodesDefaults() throws {
        #expect(try decode("{}") == CrierKit.Settings())
    }

    // partialKeepsChoices keeps stored choices, defaults the rest, and skips an unknown place or look.
    @Test func partialKeepsChoices() throws {
        let settings = try decode(
            #"{"speed": 80, "topics": ["tech", "nonsense"], "place": "floating", "look": "neon", "rotationSeconds": 45}"#
        )
        #expect(settings.speed == 80)
        #expect(settings.topics == [.tech])
        #expect(settings.place == .menuBar)
        #expect(settings.look == .automatic)
        #expect(settings.rotationSeconds == 45)
        #expect(settings.follows == Follow.defaults)
    }

    // roundTrip stores and reads back every field.
    @Test func roundTrip() throws {
        var settings = CrierKit.Settings()
        settings.place = .belowMenuBar
        settings.disabledSources = ["npr", "hn"]
        settings.tickerColor = StoredColor(red: 0.2, green: 0.4, blue: 0.6)
        settings.look = .custom
        settings.customLook.accent = StoredColor(red: 0, green: 0.5, blue: 1)
        settings.feeds = [CustomFeed(name: "Mine", url: "https://example.com/rss")]
        settings.alerts.minOutlets = 9
        let data = try JSONEncoder().encode(settings)
        #expect(try JSONDecoder().decode(CrierKit.Settings.self, from: data) == settings)
    }

    // sourcesSkipDisabled drops switched off feeds, keeps the screening feeds, and adds follows and own feeds.
    @Test func sourcesSkipDisabled() {
        var settings = CrierKit.Settings()
        settings.topics = [.tech]
        settings.disabledSources = ["hn"]
        settings.follows = [Follow(name: "Giants", query: "\"San Francisco Giants\"")]
        settings.feeds = [
            CustomFeed(name: "Mine", url: "https://example.com/rss"), CustomFeed(name: "Bad", url: "nope"),
        ]
        let ids = settings.sources.map(\.id)
        #expect(ids.contains("ars"))
        #expect(!ids.contains("hn"))
        #expect(!ids.contains("npr"))
        #expect(ids.contains("google-sports"))
        #expect(ids.contains("follow:Giants"))
        #expect(ids.contains("custom:https://example.com/rss"))
        #expect(!ids.contains { $0.contains("nope") })
    }

    // theme maps each look to band colors.
    @Test func theme() {
        var settings = CrierKit.Settings()
        #expect(settings.theme == nil)
        settings.look = .ink
        #expect(settings.theme == .dark)
        #expect(settings.theme?.isDark == true)
        settings.look = .paper
        #expect(settings.theme == .light)
        #expect(settings.theme?.isDark == false)
        settings.look = .custom
        #expect(settings.theme?.background == settings.customLook.background.color)
    }

    // storedColor survives a trip through SwiftUI's Color.
    @Test func storedColor() {
        let color = StoredColor(red: 0.25, green: 0.5, blue: 0.75, alpha: 1)
        let back = StoredColor(color.color)
        #expect(abs(back.red - 0.25) < 0.001)
        #expect(abs(back.green - 0.5) < 0.001)
        #expect(abs(back.blue - 0.75) < 0.001)
    }

    // sourceNames label feeds for the settings window.
    @Test func sourceNames() {
        let names = Dictionary(uniqueKeysWithValues: Source.catalog.map { ($0.id, $0.name) })
        #expect(names["google-top"] == "Google News")
        #expect(names["google-tech"] == "Google News Tech and software")
        #expect(names["guardian-world"] == "The Guardian World")
        #expect(names["npr"] == "NPR")
    }

    // followMatches needs the follow's name and refuses betting and schedule pages.
    @Test func followMatches() {
        let follow = Follow(name: "49ers", query: "\"San Francisco 49ers\"")
        #expect(follow.matches("49ers beat Seahawks in overtime"))
        #expect(!follow.matches("Seahawks beat Rams in overtime"))
        #expect(!follow.matches("49ers vs Seahawks odds and picks"))
        #expect(Follow(name: "Giants", query: "").source == nil)
    }
}
