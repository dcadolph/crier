import CoreGraphics
import Testing

@testable import CrierKit

// MarqueeClockTests covers the shared scroll that keeps split ticker panels in step.
struct MarqueeClockTests {
    // scroll has moved 5 points by time 10 and runs at 40 points a second.
    let scroll = Scroll(start: 10, distance: 5, speed: 40)

    // distance grows with time while moving and stands still while held or stopped.
    @Test func distance() {
        #expect(scroll.distance(at: 12) == 85)
        #expect(scroll.distance(at: 9) == 5)
        var held = scroll
        held.held = true
        #expect(held.distance(at: 100) == 5)
        var stopped = scroll
        stopped.speed = 0
        #expect(stopped.distance(at: 100) == 5)
    }

    // set keeps the distance so far and carries on from the new time at the new speed.
    @Test func set() {
        var changed = scroll
        changed.set(speed: 20, held: true, at: 12)
        #expect(changed.distance(at: 100) == 85)
        changed.set(speed: 20, held: false, at: 50)
        #expect(changed.start == 50)
        #expect(changed.distance(at: 51) == 105)
    }

    // phase wraps the panel's offset plus the distance into one copy of the row.
    @Test func phase() {
        #expect(scroll.phase(at: 12, offset: 30, width: 100) == 15)
        #expect(scroll.phase(at: 12, offset: 0, width: 0) == 0)
        #expect(Scroll.wrap(-10, 100) == 90)
    }

    // splitPanelsShareRow finds the same place in the row from either side of a gap, so a headline that leaves the
    // right panel comes out of the left one as if it ran on behind the clock.
    @Test func splitPanelsShareRow() {
        let left = scroll.position(of: 310, at: 12, offset: 0, width: 1000)
        let right = scroll.position(of: 10, at: 12, offset: 300, width: 1000)
        #expect(left == right)
        #expect(left == 395)
    }

    // copies covers a panel wider than the row with enough copies, and never draws fewer than two.
    @Test func copies() {
        #expect(Scroll.copies(width: 500, panel: 1200) == 4)
        #expect(Scroll.copies(width: 1000, panel: 300) == 2)
        #expect(Scroll.copies(width: 1000, panel: 1000) == 2)
        #expect(Scroll.copies(width: 0, panel: 300) == 2)
    }

    // hoverHoldsAll holds the clock while the mouse is over any panel and tells every listener.
    @MainActor @Test func hoverHoldsAll() {
        let clock = MarqueeClock()
        let left = Panel()
        let right = Panel()
        var calls = 0
        clock.listen(left) { calls += 1 }
        clock.listen(right) { calls += 1 }
        clock.hover(left, true)
        #expect(clock.scroll.held)
        #expect(calls == 2)
        clock.hover(right, true)
        clock.hover(left, false)
        #expect(clock.scroll.held)
        clock.hover(right, false)
        #expect(!clock.scroll.held)
        clock.hover(right, false)
        #expect(calls == 8)
    }

    // stopReleasesHover lets the others run when a hovered panel goes away, and stops telling it.
    @MainActor @Test func stopReleasesHover() {
        let clock = MarqueeClock()
        let gone = Panel()
        let kept = Panel()
        var goneCalls = 0
        clock.listen(gone) { goneCalls += 1 }
        clock.listen(kept) {}
        clock.hover(gone, true)
        clock.stop(gone)
        #expect(!clock.scroll.held)
        #expect(goneCalls == 1)
    }

    // pauseHolds holds the clock at the caller's request and changes nothing when the settings repeat.
    @MainActor @Test func pauseHolds() {
        let clock = MarqueeClock()
        let panel = Panel()
        var calls = 0
        clock.listen(panel) { calls += 1 }
        clock.configure(speed: 40, paused: false)
        #expect(calls == 0)
        clock.configure(speed: 40, paused: true)
        #expect(clock.scroll.held)
        clock.configure(speed: 60, paused: false)
        #expect(clock.scroll.speed == 60)
        #expect(!clock.scroll.held)
        #expect(calls == 2)
    }

    // Panel stands in for a ticker panel.
    final class Panel {}
}
