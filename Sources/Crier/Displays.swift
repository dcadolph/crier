import AppKit

import CrierKit

// Display is one connected screen as Crier sees it.
@MainActor
struct Display {
    // id is the display number, which can change when displays reconnect.
    let id: CGDirectDisplayID
    // screen is the AppKit screen for the display.
    let screen: NSScreen

    // all returns every connected display, the one holding the menu bar first.
    static func all() -> [Display] {
        NSScreen.screens.compactMap { screen in
            let key = NSDeviceDescriptionKey("NSScreenNumber")
            guard let id = screen.deviceDescription[key] as? CGDirectDisplayID else {
                return nil
            }
            return Display(id: id, screen: screen)
        }
    }

    // shown returns the displays that show the ticker under the given settings.
    static func shown(_ settings: Settings) -> [Display] {
        let displays = all()
        return settings.allDisplays ? displays : Array(displays.prefix(1))
    }

    // bar describes the display's menu bar, with zero height when the bar is hidden.
    func bar() -> Bar {
        let frame = screen.frame
        let height = max(0, frame.maxY - screen.visibleFrame.maxY)
        var notch: CGRect?
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            let minX = frame.minX + left.width
            let maxX = frame.maxX - right.width
            if maxX > minX {
                notch = CGRect(x: minX, y: frame.maxY - height, width: maxX - minX, height: height)
            }
        }
        return Bar(frame: frame, height: height, notch: notch)
    }
}
