import CoreGraphics

// Bar describes one display's menu bar.
public struct Bar: Sendable, Equatable {
    // frame is the display's full frame in screen coordinates.
    public let frame: CGRect
    // height is the menu bar's height, or zero when the bar is hidden.
    public let height: CGFloat
    // notch is the camera housing's area in the bar, if the display has one.
    public let notch: CGRect?

    // init builds a bar.
    public init(frame: CGRect, height: CGFloat, notch: CGRect? = nil) {
        self.frame = frame
        self.height = height
        self.notch = notch
    }
}

// Placement works out where the ticker panel goes.
public enum Placement {
    // stripHeight is the height of the strip below the menu bar.
    public static let stripHeight: CGFloat = 24
    // margin keeps the menu bar ticker clear of the screen edges and the notch.
    public static let margin: CGFloat = 12

    // frame returns the ticker panel's frame, or nil when the menu bar is hidden and the ticker should be too.
    public static func frame(bar: Bar, settings: Settings) -> CGRect? {
        guard bar.height > 0 else {
            return nil
        }
        let top = bar.frame.maxY - bar.height
        switch settings.place {
        case .belowMenuBar:
            return CGRect(x: bar.frame.minX, y: top - stripHeight, width: bar.frame.width, height: stripHeight)
        case .menuBar:
            let width = min(CGFloat(settings.width), bar.frame.width - 2 * margin)
            guard width > 0 else {
                return nil
            }
            var x = bar.frame.midX + CGFloat(settings.offset) - width / 2
            x = min(max(x, bar.frame.minX + margin), bar.frame.maxX - margin - width)
            var rect = CGRect(x: x, y: top, width: width, height: bar.height)
            if let notch = bar.notch, rect.intersects(notch.insetBy(dx: -margin, dy: 0)) {
                let right = notch.maxX + margin
                let left = notch.minX - margin - width
                if right + width <= bar.frame.maxX - margin, settings.offset >= 0 || left < bar.frame.minX + margin {
                    rect.origin.x = right
                } else if left >= bar.frame.minX + margin {
                    rect.origin.x = left
                } else {
                    rect.origin.x = right
                    rect.size.width = max(0, bar.frame.maxX - margin - right)
                }
            }
            return rect.width > 0 ? rect : nil
        }
    }
}
