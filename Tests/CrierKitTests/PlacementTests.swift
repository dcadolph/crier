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
        settings.width = 400
        #expect(Placement.frame(bar: notched, settings: settings)?.minX == 858)
        settings.offset = -10
        #expect(Placement.frame(bar: notched, settings: settings)?.maxX == 654)
    }
}
