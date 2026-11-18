import AppKit
import ApplicationServices

import CrierKit

// BarRoom measures what else takes space in the menu bar and reports when it changes: where the frontmost
// app's menus end, where the status items start, and where Fuginaut's clock sits. Status items do not show in
// the window list, so their edge comes from Crier's own bell, which macOS adds left of the items already there.
// The menus' edge needs Accessibility permission. Without it the settings' menu room stands in.
@MainActor
final class BarRoom {
    // fuginaut is the clock app whose window the ticker steps around.
    static let fuginaut = "com.dcadolph.fuginaut"
    // interval is how often the room is measured again, since the clock and the status items move without notice.
    static let interval = Duration.seconds(2)
    // itemsFallback is the room kept for status items when the bell's place is unknown.
    static let itemsFallback: CGFloat = 700
    // timeout caps how long a slow app can hold up the menus' measurement, in seconds.
    static let timeout: Float = 0.25

    // store holds the live settings.
    private let store: SettingsStore
    // bell returns the bell's frame in screen coordinates, or nil when it is not in the bar.
    private let bell: @MainActor () -> NSRect?
    // room is the latest measurement.
    private(set) var room = Room()
    // onChange runs after the room changes.
    var onChange: (@MainActor () -> Void)?
    // ticking measures the room again on every interval.
    private var ticking: Task<Void, Never>?

    // init measures the room and follows app switches, display changes, and settings changes.
    init(store: SettingsStore, bell: @escaping @MainActor () -> NSRect?) {
        self.store = store
        self.bell = bell
        let center = NSWorkspace.shared.notificationCenter
        for name in [
            NSWorkspace.didActivateApplicationNotification, NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
        ] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.update()
                }
            }
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.update()
            }
        }
        store.onChange { [weak self] _ in
            self?.update()
        }
        room = measure()
        ticking = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.interval)
                guard let self else {
                    return
                }
                self.update()
            }
        }
    }

    // trusted reports whether Crier may read other apps' menus.
    static var trusted: Bool {
        AXIsProcessTrusted()
    }

    // askForTrust shows the system's Accessibility prompt, which adds Crier to the list in System Settings.
    static func askForTrust() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    // update measures the room and reports a change. Nothing is measured while the ticker is off the menu bar.
    func update() {
        let settings = store.settings
        guard settings.tickerOn, settings.place == .menuBar else {
            return
        }
        let new = measure()
        guard new != room else {
            return
        }
        room = new
        onChange?()
    }

    // measure reads the menus' end, the status items' start, and Fuginaut's windows.
    private func measure() -> Room {
        Room(
            menus: menusEnd() ?? CGFloat(store.settings.menuRoom), items: itemsStart() ?? Self.itemsFallback,
            obstacles: fuginautWindows())
    }

    // itemsStart returns how far the status items reach in from the right edge of the bell's display.
    private func itemsStart() -> CGFloat? {
        guard let frame = bell(), let screen = NSScreen.screens.first(where: { $0.frame.intersects(frame) }) else {
            return nil
        }
        return screen.frame.maxX - frame.minX
    }

    // menusEnd returns how far the frontmost app's menus reach from the left edge of the main display, or nil
    // without Accessibility permission.
    private func menusEnd() -> CGFloat? {
        guard Self.trusted, let app = NSWorkspace.shared.frontmostApplication,
            let main = NSScreen.screens.first
        else {
            return nil
        }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, Self.timeout)
        guard let bar = attribute(element, kAXMenuBarAttribute), CFGetTypeID(bar) == AXUIElementGetTypeID() else {
            return nil
        }
        let menus = (attribute(bar as! AXUIElement, kAXChildrenAttribute) as? [AXUIElement]) ?? []
        var end: CGFloat?
        for menu in menus {
            guard let position = point(menu, kAXPositionAttribute), let size = size(menu, kAXSizeAttribute) else {
                continue
            }
            end = max(end ?? 0, position.x + size.width)
        }
        return end.map { $0 - main.frame.minX }
    }

    // fuginautWindows returns Fuginaut's on-screen windows at status bar level, which hold its clock.
    private func fuginautWindows() -> [CGRect] {
        let pids = Set(
            NSRunningApplication.runningApplications(withBundleIdentifier: Self.fuginaut).map(\.processIdentifier))
        guard !pids.isEmpty, let main = NSScreen.screens.first,
            let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]]
        else {
            return []
        }
        let level = Int(CGWindowLevelForKey(.statusWindow))
        return list.compactMap { window in
            guard let pid = window[kCGWindowOwnerPID as String] as? pid_t, pids.contains(pid),
                window[kCGWindowLayer as String] as? Int == level,
                let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                let rect = CGRect(dictionaryRepresentation: bounds)
            else {
                return nil
            }
            return Room.screenRect(rect, mainHeight: main.frame.height)
        }
    }

    // attribute reads one Accessibility attribute.
    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
            return nil
        }
        return value
    }

    // point reads an Accessibility attribute that holds a point.
    private func point(_ element: AXUIElement, _ name: String) -> CGPoint? {
        guard let value = attribute(element, name), CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        var point = CGPoint.zero
        return AXValueGetValue(value as! AXValue, .cgPoint, &point) ? point : nil
    }

    // size reads an Accessibility attribute that holds a size.
    private func size(_ element: AXUIElement, _ name: String) -> CGSize? {
        guard let value = attribute(element, name), CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        var size = CGSize.zero
        return AXValueGetValue(value as! AXValue, .cgSize, &size) ? size : nil
    }
}
