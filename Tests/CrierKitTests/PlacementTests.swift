import CoreGraphics
import Testing

@testable import CrierKit

// PlacementTests covers where the ticker panel goes.
struct PlacementTests {
    // bar is a 1512 by 982 display with a 33 point menu bar.
    let bar = Bar(frame: CGRect(x: 0, y: 0, width: 1512, height: 982), height: 33)

    // hiddenBar hides the ticker.
    @Test func hiddenBar() {
        let hidden = Bar(frame: bar.frame, height: 0)
        #expect(Placement.frame(bar: hidden, settings: Settings()) == nil)
    }

    // strip spans the display just under the bar.
    @Test func strip() {
        var settings = Settings()
        settings.place = .belowMenuBar
        #expect(Placement.frame(bar: bar, settings: settings) == CGRect(x: 0, y: 925, width: 1512, height: 24))
    }

    // centered sits in the middle of the bar, and an offset shifts it until the screen edge stops it.
    @Test func centeredAndOffset() {
        var settings = Settings()
        settings.fill = false
        settings.width = 500
        #expect(Placement.frame(bar: bar, settings: settings) == CGRect(x: 506, y: 949, width: 500, height: 33))
        settings.offset = 10_000
        #expect(Placement.frame(bar: bar, settings: settings)?.maxX == 1500)
        settings.width = 5000
        settings.offset = 0
        #expect(Placement.frame(bar: bar, settings: settings)?.width == 1488)
    }

    // notch moves the ticker beside the camera housing.
    @Test func notch() {
        let notched = Bar(frame: bar.frame, height: 33, notch: CGRect(x: 666, y: 949, width: 180, height: 33))
        var settings = Settings()
        settings.fill = false
        settings.width = 400
        #expect(Placement.frame(bar: notched, settings: settings)?.minX == 858)
        settings.offset = -10
        #expect(Placement.frame(bar: notched, settings: settings)?.maxX == 654)
    }

    // wide is the owner's 5120 point display with a 30 point bar, the main display, so screen y starts at 0.
    let wide = Bar(frame: CGRect(x: 0, y: 0, width: 5120, height: 1440), height: 30)
    // clock is Fuginaut's clock, 160 points wide and centered in the wide bar.
    let clock = CGRect(x: 2480, y: 1410, width: 160, height: 30)
    // room keeps 900 points for menus and 700 for status items.
    var room: Room {
        Room(menus: 900, items: 700)
    }

    // menuBar returns default menu bar settings with the given position, fill, and width.
    private func menuBar(_ position: Position, fill: Bool = false, width: Double = 600) -> CrierKit.Settings {
        var settings = CrierKit.Settings()
        settings.position = position
        settings.fill = fill
        settings.width = width
        return settings
    }

    // fillSpansOpenBar runs from the menus to the status items, each with a margin.
    @Test func fillSpansOpenBar() {
        let frame = Placement.frame(bar: wide, settings: menuBar(.center, fill: true), room: room)
        #expect(frame == CGRect(x: 912, y: 1410, width: 3496, height: 30))
    }

    // fillSides stops at the middle of the bar, or at the clock when it is there.
    @Test func fillSides() {
        let left = Placement.frame(bar: wide, settings: menuBar(.leftOfCenter, fill: true), room: room)
        #expect(left?.minX == 912)
        #expect(left?.maxX == 2548)
        let right = Placement.frame(bar: wide, settings: menuBar(.rightOfCenter, fill: true), room: room)
        #expect(right?.minX == 2572)
        #expect(right?.maxX == 4408)
        var clocked = room
        clocked.obstacles = [clock]
        let leftOfClock = Placement.frame(bar: wide, settings: menuBar(.leftOfCenter, fill: true), room: clocked)
        #expect(leftOfClock?.maxX == 2468)
        let rightOfClock = Placement.frame(bar: wide, settings: menuBar(.rightOfCenter, fill: true), room: clocked)
        #expect(rightOfClock?.minX == 2652)
    }

    // fillCenterTakesWiderSide picks the wider stretch beside the clock.
    @Test func fillCenterTakesWiderSide() {
        let frame = Placement.frame(
            bar: wide, settings: menuBar(.center, fill: true), room: Room(menus: 900, items: 300, obstacles: [clock]))
        #expect(frame == CGRect(x: 2652, y: 1410, width: 2156, height: 30))
    }

    // positions place a fixed width ticker in the middle, ending left of it, or starting right of it.
    @Test func positions() {
        #expect(Placement.frame(bar: wide, settings: menuBar(.center), room: room)?.minX == 2260)
        #expect(Placement.frame(bar: wide, settings: menuBar(.leftOfCenter), room: room)?.maxX == 2548)
        #expect(Placement.frame(bar: wide, settings: menuBar(.rightOfCenter), room: room)?.minX == 2572)
    }

    // clockSteps moves each position clear of Fuginaut's clock: left of center to its left, right of center to
    // its right, and center the shorter way, which is right on a tie.
    @Test func clockSteps() {
        let clocked = Room(menus: 900, items: 700, obstacles: [clock])
        #expect(Placement.frame(bar: wide, settings: menuBar(.leftOfCenter), room: clocked)?.maxX == 2468)
        #expect(Placement.frame(bar: wide, settings: menuBar(.rightOfCenter), room: clocked)?.minX == 2652)
        #expect(Placement.frame(bar: wide, settings: menuBar(.center), room: clocked)?.minX == 2652)
        var nudged = menuBar(.center)
        nudged.offset = -20
        #expect(Placement.frame(bar: wide, settings: nudged, room: clocked)?.maxX == 2468)
    }

    // clockElsewhere ignores a clock on another display and a clock that leaves the ticker alone.
    @Test func clockElsewhere() {
        let otherDisplay = CGRect(x: 6000, y: 1410, width: 160, height: 30)
        let farLeft = CGRect(x: 1000, y: 1410, width: 160, height: 30)
        let room = Room(menus: 900, items: 700, obstacles: [otherDisplay, farLeft])
        #expect(Placement.frame(bar: wide, settings: menuBar(.center), room: room)?.minX == 2260)
    }

    // tightShrinks fits a ticker wider than any open stretch into the widest one, and hides it when even that is
    // too narrow.
    @Test func tightShrinks() {
        let clocked = Room(menus: 900, items: 700, obstacles: [clock])
        let frame = Placement.frame(bar: wide, settings: menuBar(.center, width: 3000), room: clocked)
        #expect(frame?.minX == 2652)
        #expect(frame?.maxX == 4408)
        let full = Room(menus: 2400, items: 2500, obstacles: [clock])
        #expect(Placement.frame(bar: wide, settings: menuBar(.center), room: full) == nil)
        #expect(Placement.frame(bar: wide, settings: menuBar(.center), room: Room(menus: 3000, items: 3000)) == nil)
    }

    // screenRect flips a window list rectangle into screen coordinates.
    @Test func screenRect() {
        let rect = Room.screenRect(CGRect(x: 2480, y: 0, width: 160, height: 30), mainHeight: 1440)
        #expect(rect == clock)
    }
}
