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
}
