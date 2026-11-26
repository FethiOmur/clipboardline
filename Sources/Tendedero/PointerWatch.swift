import Foundation

/// When the app watches the pointer, so an idle app does not wake.
///
/// The pointer used to be read 30 times a second whenever the line held
/// anything, even tucked away. Now it is read only when something can react:
/// tucked away, only "When the pointer rests in the menu bar" needs it, and
/// it needs polling, since a resting pointer sends no events. Open, mouse
/// events drive the checks, plus one wake for the next deadline (the end of a
/// peek, the retract delay) and a slow safety re-check while the pointer is
/// over the stack or something other than the pointer keeps it open.
enum PointerWatch {
    /// The menu-bar dwell tick, as before.
    static let dwellInterval: TimeInterval = 1.0 / 30.0
    /// The safety re-check while the pointer is over the open stack, or while
    /// a drag, a menu, a picker or an operation keeps it open.
    static let busyInterval: TimeInterval = 0.25
    /// Pointer events are folded into at most one check per this interval.
    static let eventCoalescing: TimeInterval = 1.0 / 60.0

    struct Need: Equatable {
        /// Tick at `dwellInterval` while tucked away.
        var pollsForMenuBarDwell: Bool
        /// Mouse-event monitors that check the pointer when it moves.
        var followsPointer: Bool
    }

    static func need(wanted: Bool, revealed: Bool, opensFromMenuBar: Bool) -> Need {
        guard wanted else { return Need(pollsForMenuBarDwell: false, followsPointer: false) }
        if revealed { return Need(pollsForMenuBarDwell: false, followsPointer: true) }
        return Need(pollsForMenuBarDwell: opensFromMenuBar, followsPointer: false)
    }

    /// Seconds until the open stack must be checked again without a pointer
    /// event, or nil when only the pointer (or the shortcut) can change
    /// anything. `otherBusy` is every reason to stay open except `pinned`
    /// and the peek.
    static func nextCheck(now: Date, inside: Bool, pinned: Bool, awaySince: Date?, peekUntil: Date,
                          otherBusy: Bool, retractDelay: TimeInterval) -> TimeInterval? {
        if inside { return busyInterval }
        // Opened on purpose: it stays until the pointer has visited it, which
        // a pointer event reports.
        if pinned { return nil }
        var waits: [TimeInterval] = []
        if let awaySince { waits.append(awaySince.addingTimeInterval(retractDelay).timeIntervalSince(now)) }
        if peekUntil > now { waits.append(peekUntil.timeIntervalSince(now)) }
        if otherBusy { waits.append(busyInterval) }
        return waits.min().map { max(0, $0) }
    }

    // MARK: Closing at the right edge

    /// The last points of the screen, beyond the stack's ~10 pt inset.
    static let closingEdgeWidth: CGFloat = 2

    /// Whether the pointer is in the screen's last `closingEdgeWidth` points
    /// on the right.
    static func isAtClosingEdge(_ point: CGPoint, screen: CGRect) -> Bool {
        point.x >= screen.maxX - closingEdgeWidth && point.x <= screen.maxX
            && point.y >= screen.minY && point.y <= screen.maxY
    }

    /// The open stack hides when the pointer arrives at the right edge: it
    /// was not there at the previous check (or when the stack opened), so a
    /// pointer already resting there does not close it. A drag, menu, press,
    /// preview or picker keeps it open.
    static func closesAtEdge(enabled: Bool, wasAtEdge: Bool, atEdge: Bool, blocked: Bool) -> Bool {
        enabled && atEdge && !wasAtEdge && !blocked
    }

    /// Remembers where the pointer was at the last check of the open stack.
    struct EdgeArrival {
        private(set) var wasAtEdge = false
        /// The stack opened with the pointer here; resting at the edge then is not an arrival.
        mutating func opened(atEdge: Bool) { wasAtEdge = atEdge }
        /// One pointer check; true when the stack must hide now.
        mutating func check(atEdge: Bool, blocked: Bool, enabled: Bool) -> Bool {
            defer { wasAtEdge = atEdge }
            return PointerWatch.closesAtEdge(enabled: enabled, wasAtEdge: wasAtEdge, atEdge: atEdge, blocked: blocked)
        }
    }
}
