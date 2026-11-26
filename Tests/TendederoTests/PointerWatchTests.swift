import XCTest
@testable import Tendedero

/// An idle app must not wake to read the pointer. These pin down when it may.
final class PointerWatchTests: XCTestCase {
    private let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
    private let retract: TimeInterval = 0.5

    func testTuckedAwayStackWatchesNothingWithMenuBarRevealOff() {
        // The default: items hang, the stack is hidden, nothing reads the pointer.
        XCTAssertEqual(PointerWatch.need(wanted: true, revealed: false, opensFromMenuBar: false),
                       .init(pollsForMenuBarDwell: false, followsPointer: false))
    }

    func testMenuBarRevealPollsOnlyWhileTuckedAway() {
        XCTAssertEqual(PointerWatch.need(wanted: true, revealed: false, opensFromMenuBar: true),
                       .init(pollsForMenuBarDwell: true, followsPointer: false))
        XCTAssertEqual(PointerWatch.need(wanted: true, revealed: true, opensFromMenuBar: true),
                       .init(pollsForMenuBarDwell: false, followsPointer: true))
    }

    func testNoLineWatchesNothing() {
        for menuBar in [false, true] {
            for revealed in [false, true] {
                XCTAssertEqual(PointerWatch.need(wanted: false, revealed: revealed, opensFromMenuBar: menuBar),
                               .init(pollsForMenuBarDwell: false, followsPointer: false))
            }
        }
    }

    func testOpenStackFollowsPointerEventsInsteadOfPolling() {
        XCTAssertEqual(PointerWatch.need(wanted: true, revealed: true, opensFromMenuBar: false),
                       .init(pollsForMenuBarDwell: false, followsPointer: true))
    }

    func testPinnedStackAwayFromPointerNeedsNoTimer() {
        // Opened with the shortcut: only a pointer visit can release it.
        XCTAssertNil(PointerWatch.nextCheck(now: now, inside: false, pinned: true, awaySince: nil,
                                            peekUntil: .distantPast, otherBusy: true, retractDelay: retract))
    }

    func testPeekWakesOnceWhenItEnds() {
        let wait = PointerWatch.nextCheck(now: now, inside: false, pinned: false, awaySince: nil,
                                          peekUntil: now.addingTimeInterval(4), otherBusy: false, retractDelay: retract)
        XCTAssertEqual(wait ?? -1, 4, accuracy: 0.0001)
    }

    func testRetractWakesAtTheEndOfTheDelay() {
        let wait = PointerWatch.nextCheck(now: now, inside: false, pinned: false, awaySince: now.addingTimeInterval(-0.2),
                                          peekUntil: .distantPast, otherBusy: false, retractDelay: retract)
        XCTAssertEqual(wait ?? -1, 0.3, accuracy: 0.0001)
        let overdue = PointerWatch.nextCheck(now: now, inside: false, pinned: false, awaySince: now.addingTimeInterval(-2),
                                             peekUntil: .distantPast, otherBusy: false, retractDelay: retract)
        XCTAssertEqual(overdue, 0)
    }

    func testSomethingElseHoldingItOpenIsRecheckedSlowly() {
        // A picker or an operation can end without a pointer event.
        XCTAssertEqual(PointerWatch.nextCheck(now: now, inside: false, pinned: false, awaySince: nil,
                                              peekUntil: .distantPast, otherBusy: true, retractDelay: retract),
                       PointerWatch.busyInterval)
        let peekSooner = PointerWatch.nextCheck(now: now, inside: false, pinned: false, awaySince: nil,
                                                peekUntil: now.addingTimeInterval(0.1), otherBusy: true, retractDelay: retract)
        XCTAssertEqual(peekSooner ?? -1, 0.1, accuracy: 0.0001)
    }

    func testPointerOverTheStackGetsASafetyRecheck() {
        XCTAssertEqual(PointerWatch.nextCheck(now: now, inside: true, pinned: true, awaySince: nil,
                                              peekUntil: .distantPast, otherBusy: false, retractDelay: retract),
                       PointerWatch.busyInterval)
    }

    func testRecheckIsFarSlowerThanTheOldThirtyHertzTick() {
        XCTAssertGreaterThanOrEqual(PointerWatch.busyInterval, 0.2)
    }
}
