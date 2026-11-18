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

    // band is the strip of the display the menu bar covers.
    public var band: CGRect {
        CGRect(x: frame.minX, y: frame.maxY - height, width: frame.width, height: height)
    }
}

// Room is what else takes space in the menu bar: the app menus from the left edge, the status items from the
// right edge, and windows such as Fuginaut's clock that the ticker steps around.
public struct Room: Sendable, Equatable {
    // menus is how far the app menus reach from the bar's left edge.
    public var menus: CGFloat
    // items is how far the status items reach in from the bar's right edge.
    public var items: CGFloat
    // obstacles are other windows sitting in a bar, in screen coordinates.
    public var obstacles: [CGRect]

    // init builds a room.
    public init(menus: CGFloat = 0, items: CGFloat = 0, obstacles: [CGRect] = []) {
        self.menus = menus
        self.items = items
        self.obstacles = obstacles
    }

    // screenRect turns a window list rectangle, whose origin is the top left of the main display, into screen
    // coordinates, whose origin is the bottom left. mainHeight is the main display's height.
    public static func screenRect(_ rect: CGRect, mainHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: mainHeight - rect.maxY, width: rect.width, height: rect.height)
    }
}

// Placement works out where the ticker panel goes.
public enum Placement {
    // stripHeight is the height of the strip below the menu bar.
    public static let stripHeight: CGFloat = 24
    // margin keeps the menu bar ticker clear of the screen edges, the menus, the status items, and obstacles.
    public static let margin: CGFloat = 12
    // minWidth is the narrowest ticker worth showing. With less room than this the ticker hides.
    public static let minWidth: CGFloat = 120

    // frame returns the ticker panel's frame, or nil when the menu bar is hidden or too full to hold the ticker.
    public static func frame(bar: Bar, settings: Settings, room: Room = Room()) -> CGRect? {
        guard bar.height > 0 else {
            return nil
        }
        let band = bar.band
        switch settings.place {
        case .belowMenuBar:
            return CGRect(x: band.minX, y: band.minY - stripHeight, width: band.width, height: stripHeight)
        case .menuBar:
            let open = spans(bar: bar, room: room)
            let anchor = band.midX + CGFloat(settings.offset)
            let span =
                settings.fill
                ? filled(open, anchor: anchor, position: settings.position)
                : fitted(open, anchor: anchor, position: settings.position, width: CGFloat(settings.width))
            guard let span, span.width >= minWidth else {
                return nil
            }
            return CGRect(x: span.lo, y: band.minY, width: span.width, height: band.height)
        }
    }

    // Span is a stretch of the bar from lo to hi.
    struct Span: Equatable {
        var lo: CGFloat
        var hi: CGFloat

        // width is the span's length.
        var width: CGFloat {
            hi - lo
        }
    }

    // spans returns the open stretches of the bar: inside the menus and the status items, and clear of the
    // notch and every obstacle in this bar, each with a margin around it.
    static func spans(bar: Bar, room: Room) -> [Span] {
        let band = bar.band
        let lo = band.minX + max(0, room.menus) + margin
        let hi = band.maxX - max(0, room.items) - margin
        guard hi > lo else {
            return []
        }
        let blocks = ([bar.notch].compactMap { $0 } + room.obstacles)
            .filter { $0.intersects(band) }
            .map { Span(lo: $0.minX - margin, hi: $0.maxX + margin) }
            .sorted { $0.lo < $1.lo }
        var open: [Span] = []
        var start = lo
        for block in blocks {
            if block.lo > start {
                open.append(Span(lo: start, hi: min(block.lo, hi)))
            }
            start = max(start, block.hi)
            if start >= hi {
                break
            }
        }
        if start < hi {
            open.append(Span(lo: start, hi: hi))
        }
        return open.filter { $0.width > 0 }
    }

    // filled returns the widest open stretch on the position's side of the anchor, or anywhere for center.
    static func filled(_ open: [Span], anchor: CGFloat, position: Position) -> Span? {
        let pieces = open.compactMap { span -> Span? in
            var piece = span
            switch position {
            case .center:
                break
            case .leftOfCenter:
                piece.hi = min(piece.hi, anchor - margin)
            case .rightOfCenter:
                piece.lo = max(piece.lo, anchor + margin)
            }
            return piece.width > 0 ? piece : nil
        }
        return pieces.max { $0.width < $1.width }
    }

    // fitted places a ticker of the given width at the position, then steps it the shortest way to an open
    // stretch that holds it. A tie steps toward the position's own side, and right for center. When no
    // stretch is wide enough, the ticker shrinks into the widest one.
    static func fitted(_ open: [Span], anchor: CGFloat, position: Position, width: CGFloat) -> Span? {
        guard width > 0 else {
            return nil
        }
        let want: CGFloat
        switch position {
        case .center: want = anchor - width / 2
        case .leftOfCenter: want = anchor - margin - width
        case .rightOfCenter: want = anchor + margin
        }
        let leftward = position == .leftOfCenter
        var best: (x: CGFloat, move: CGFloat)?
        for span in open where span.width >= width {
            let x = min(max(want, span.lo), span.hi - width)
            let move = abs(x - want)
            guard let current = best else {
                best = (x, move)
                continue
            }
            let tie = abs(move - current.move) < 0.5
            if move < current.move - 0.5 || (tie && (leftward ? x < current.x : x > current.x)) {
                best = (x, move)
            }
        }
        if let best {
            return Span(lo: best.x, hi: best.x + width)
        }
        return open.max { $0.width < $1.width }
    }
}
