import Foundation
import QuartzCore

// Scroll is how far the ticker row has moved, as plain math: the distance at a start time plus speed times the
// time since, frozen while held. Every panel that shares a scroll shows the same row at the same place.
public struct Scroll: Sendable, Equatable {
    // start is the media time the distance was last taken at, in seconds.
    public var start: Double
    // distance is how far the row had moved at start, in points.
    public var distance: Double
    // speed is how fast the row moves, in points per second.
    public var speed: Double
    // held stops the row.
    public var held: Bool

    // init builds a scroll.
    public init(start: Double = 0, distance: Double = 0, speed: Double = 40, held: Bool = false) {
        self.start = start
        self.distance = distance
        self.speed = speed
        self.held = held
    }

    // moving reports whether the row is on the move.
    public var moving: Bool {
        !held && speed > 0
    }

    // distance returns how far the row has moved at the given media time.
    public func distance(at time: Double) -> Double {
        moving ? distance + max(0, time - start) * speed : distance
    }

    // set changes the speed and the hold at the given media time, keeping the distance so far.
    public mutating func set(speed: Double, held: Bool, at time: Double) {
        distance = distance(at: time)
        start = time
        self.speed = speed
        self.held = held
    }

    // phase returns where in one copy of the row the left edge of a panel sits at the given media time. offset
    // is the panel's left edge measured from its display's left edge, so panels with a gap between them show the
    // row as if it ran on behind the gap.
    public func phase(at time: Double, offset: CGFloat, width: CGFloat) -> CGFloat {
        Self.wrap(offset + CGFloat(distance(at: time)), width)
    }

    // position returns where in one copy of the row a point in a panel falls at the given media time.
    public func position(of x: CGFloat, at time: Double, offset: CGFloat, width: CGFloat) -> CGFloat {
        Self.wrap(x + phase(at: time, offset: offset, width: width), width)
    }

    // copies returns how many copies of the row a panel of the given width needs so the row never runs out while
    // it scrolls through one copy.
    public static func copies(width: CGFloat, panel: CGFloat) -> Int {
        guard width > 0 else {
            return 2
        }
        return max(2, Int((panel / width).rounded(.up)) + 1)
    }

    // wrap returns value modulo width, kept in zero up to width.
    static func wrap(_ value: CGFloat, _ width: CGFloat) -> CGFloat {
        guard width > 0 else {
            return 0
        }
        let rest = value.truncatingRemainder(dividingBy: width)
        return rest < 0 ? rest + width : rest
    }
}

// MarqueeClock is the scroll that several ticker panels share, such as the two sides of a ticker split by a
// clock. Hovering any of them holds all of them. Each panel runs its own Core Animation scroll from the clock's
// start time, so the panels move in step with no timer.
@MainActor
public final class MarqueeClock {
    // scroll is the shared scroll.
    public private(set) var scroll: Scroll
    // paused holds the ticker at the caller's request.
    private var paused = false
    // hovered holds the ids of the panels the mouse is over.
    private var hovered: Set<ObjectIdentifier> = []
    // listeners run after the scroll changes, keyed by the panel that registered them.
    private var listeners: [ObjectIdentifier: @MainActor () -> Void] = [:]

    // init builds a clock that starts now.
    public init() {
        scroll = Scroll(start: CACurrentMediaTime())
    }

    // now returns the media time Core Animation runs on.
    public static var now: Double {
        CACurrentMediaTime()
    }

    // configure sets the speed and the caller's pause, telling every panel when either changes.
    public func configure(speed: Double, paused: Bool) {
        guard speed != scroll.speed || paused != self.paused else {
            return
        }
        self.paused = paused
        apply(speed: speed)
    }

    // hover records whether the mouse is over a panel, holding every panel while it is over any of them.
    public func hover(_ panel: AnyObject, _ over: Bool) {
        let id = ObjectIdentifier(panel)
        let changed = over ? hovered.insert(id).inserted : hovered.remove(id) != nil
        if changed {
            apply(speed: scroll.speed)
        }
    }

    // listen runs the action after every change to the scroll, until the panel stops listening.
    public func listen(_ panel: AnyObject, _ action: @escaping @MainActor () -> Void) {
        listeners[ObjectIdentifier(panel)] = action
    }

    // stop forgets a panel's listener and its hover.
    public func stop(_ panel: AnyObject) {
        let id = ObjectIdentifier(panel)
        listeners[id] = nil
        if hovered.remove(id) != nil {
            apply(speed: scroll.speed)
        }
    }

    // apply rebases the scroll at the current time and tells every panel.
    private func apply(speed: Double) {
        scroll.set(speed: speed, held: paused || !hovered.isEmpty, at: Self.now)
        for action in listeners.values {
            action()
        }
    }
}
