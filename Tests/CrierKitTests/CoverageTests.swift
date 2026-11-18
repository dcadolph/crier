import Foundation
import Testing

@testable import CrierKit

// RoundupCase is one roundup expectation.
struct RoundupCase: Sendable, CustomTestStringConvertible {
    // title is the headline to check.
    let title: String
    // want reports whether the title should read as a roundup.
    let want: Bool

    // testDescription labels the case in test output.
    var testDescription: String { title }
}

// roundupCases covers sentence breaks, markers, abbreviations, and punctuation single stories use.
let roundupCases: [RoundupCase] = [
    RoundupCase(  // Test 0: Two stories joined by a sentence break.
        title: "Mary Peltola flips Alaska's Senate seat. And, Nvidia won't reinstate Jensen Huang", want: true),
    RoundupCase(  // Test 1: Newsletter marker.
        title: "Morning Bid: Jensen Huang's last hurrah, and a nervy future for Nvidia", want: true),
    RoundupCase(title: "Your Evening Brief: Storms, stocks, and a Senate vote", want: true),  // Test 2: Marker.
    RoundupCase(title: "Mary Peltola flips Alaska seat, giving Democrats a 56-44 edge", want: false),  // Test 3.
    RoundupCase(title: "U.S. Senate passes budget after long night", want: false),  // Test 4: Initials.
    RoundupCase(title: "Gov. Abbott signs flood bill into law", want: false),  // Test 5: Abbreviation.
    RoundupCase(title: "RFK Jr. says agency will work to regain status", want: false),  // Test 6: Jr.
    RoundupCase(  // Test 7: A question then a sentence is one story.
        title: "Why are the 49ers so popular in Mexico? Alfredo Gutiérrez explains", want: false),
    RoundupCase(title: "Rocket lands safely.", want: false),  // Test 8: A closing period.
    RoundupCase(title: "Voyager 1 is now a full light day from Earth", want: false),  // Test 9: Plain.
]

// CoverageTests covers keywords, matching, roundups, grouping, lead choice, and ranking.
struct CoverageTests {
    // keywords drops short and stop words, folds apostrophes and case, and drops a plural s.
    @Test func keywords() {
        #expect(
            Coverage.keywords("Peltola flips Alaska's Senate seat") == ["peltola", "flip", "alaska", "senate", "seat"])
        #expect(Coverage.keywords("The new update on AI") == [])
    }

    // same needs three shared words covering half the shorter set.
    @Test func same() {
        let a: Set = ["senate", "budget", "vote", "passes"]
        #expect(Coverage.same(a, ["senate", "budget", "vote"]))
        #expect(!Coverage.same(a, ["senate", "budget", "night"]))
        let long: Set = ["senate", "budget", "vote", "one", "two", "three", "four", "five"]
        #expect(!Coverage.same(long, ["senate", "budget", "vote", "six", "seven", "eight", "nine", "ten"]))
    }

    // roundup reports digest titles.
    @Test(arguments: roundupCases) func roundup(_ test: RoundupCase) {
        #expect(Coverage.roundup(test.title) == test.want)
    }

    // groupPrefersPlainLead keeps a roundup that ranks first from leading its event.
    @Test func groupPrefersPlainLead() {
        let roundup = story(
            "Peltola flips Alaska Senate seat. And, Nvidia won't reinstate Huang", outlet: "NPR", hoursAgo: 1,
            source: "g", rank: 0)
        let plain = story("Peltola flips Alaska Senate seat for Democrats", outlet: "Post", hoursAgo: 2)
        let headlines = Coverage.group([roundup, plain])
        #expect(headlines.count == 1)
        #expect(headlines[0].lead == plain)
        #expect(headlines[0].stories == [plain, roundup])
        #expect(headlines[0].keywords == Coverage.keywords(plain.title))
    }

    // latestIsNewest dates an event by its newest report, so a story that broke yesterday and is still
    // running reads as fresh.
    @Test func latestIsNewest() {
        let old = story("Leaders open the summit in Seoul", outlet: "Wire", hoursAgo: 30)
        let new = story("Leaders open the summit in Seoul with trade talks", outlet: "Post", hoursAgo: 0.5)
        let headlines = Coverage.group([old, new])
        #expect(headlines.count == 1)
        #expect(headlines[0].first == old.published)
        #expect(headlines[0].latest == new.published)
        #expect(headline("Undated story about the harbor", outlets: 1, hoursAgo: 2).latest != nil)
    }

    // groupKeepsRoundupWhenAlone leads with a roundup when no plain title covers the event.
    @Test func groupKeepsRoundupWhenAlone() {
        let roundup = story("Morning Brief: storms sweep the plains")
        #expect(Coverage.group([roundup]).map(\.lead) == [roundup])
    }

    // groupRanks puts more outlets first, then a better editor rank, then the newest, and counts an outlet
    // once with or without "The".
    @Test func groupRanks() {
        let stories = [
            story("Quiet local council meeting ends early", outlet: "Herald", hoursAgo: 1),
            story("Storm floods coastal towns overnight", outlet: "Guardian", hoursAgo: 2.5),
            story("Storm floods coastal towns, thousands flee", outlet: "The Guardian", hoursAgo: 3),
            story("Storm floods coastal towns as rivers rise", outlet: "BBC", hoursAgo: 2),
            story("Ranked story about markets rally today", outlet: "Google", source: "g", rank: 4),
            story("Fresh story about bridge opening downtown", outlet: "Times", hoursAgo: 0.5),
        ]
        let headlines = Coverage.group(stories)
        #expect(headlines.map(\.outlets.count) == [2, 1, 1, 1])
        #expect(headlines[0].outlets == ["BBC", "Guardian"])
        #expect(headlines[1].lead.title == "Ranked story about markets rally today")
        #expect(headlines[2].lead.title == "Fresh story about bridge opening downtown")
    }
}
