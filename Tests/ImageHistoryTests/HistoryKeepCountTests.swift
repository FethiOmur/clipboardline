import AppKit
#if !STANDALONE_TESTS
import XCTest
@testable import Tendedero
#endif

/// Only the newest unsaved copies of each kind stay on the shelves.
@MainActor final class HistoryKeepCountTests: HistoryTestCase {
    private func fixture() throws -> SyntheticFixture {
        let f = try SyntheticFixture()
        // The shared fixture lifts the cap for other shelf tests.
        f.defaults.removeObject(forKey: HistoryRetention.keepCountKey)
        return f
    }
    private func store(_ f: SyntheticFixture) throws -> LibraryStore {
        try LibraryStore(defaults: f.defaults, inbox: f.inbox, now: { f.date }, moveToTrash: fixtureTrash(f.folder))
    }

    func testDefaultKeepsTheNewestTenImagesAndLeavesOriginalFilesInPlace() throws {
        let f = try fixture(); defer { f.cleanup() }
        XCTAssertEqual(HistoryRetention.keepCount(defaults: f.defaults), 10)
        let library = try store(f)
        var records = [LibraryRecord]()
        for index in 0..<12 {
            // Alternate external screenshots and the app's own clipboard copies.
            records.append(try library.captureImage(try f.image(owned: index % 2 == 0)))
            f.date += 1
        }
        let live = try library.shelfItems(.image).map(\.id)
        XCTAssertEqual(live.count, 10)
        XCTAssertEqual(Set(live), Set(records.suffix(10).map(\.id)))
        // Older copies are deleted: the app's own clipboard copy with its row,
        // the external screenshot only from history.
        for old in records.prefix(2) { XCTAssertNil(try library.item(old.id)) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: try XCTUnwrap(records[0].path)), "the app's clipboard copy is deleted")
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(records[1].path)), "an original file stays in place")
    }

    func testPinnedAndSavedItemsDoNotCountAndAreNeverRemoved() throws {
        let f = try fixture(); defer { f.cleanup() }
        let library = try store(f)
        let pinned = try XCTUnwrap(library.captureText("pinned synthetic")); f.date += 1
        let saved = try XCTUnwrap(library.captureText("saved synthetic")); f.date += 1
        try library.toggleFavorite([pinned.id]); try library.retain([saved.id])
        var copies = [UUID]()
        for index in 0..<12 { copies.append(try XCTUnwrap(library.captureText("copy synthetic \(index)")).id); f.date += 1 }
        let live = Set(try library.shelfItems(.text).map(\.id))
        XCTAssertTrue(live.contains(pinned.id)); XCTAssertNil(try library.item(saved.id)?.deletedAt)
        XCTAssertEqual(live.subtracting([pinned.id, saved.id]), Set(copies.suffix(10)))
    }

    func testTheLimitAppliesPerKind() throws {
        let f = try fixture(); defer { f.cleanup() }
        let library = try store(f)
        for index in 0..<12 { _ = try library.captureText("kind synthetic \(index)"); f.date += 1 }
        for _ in 0..<3 { _ = try library.captureImage(try f.image()); f.date += 1 }
        for index in 0..<11 { _ = try library.captureLink(try XCTUnwrap(URL(string: "https://example.com/keep/\(index)"))); f.date += 1 }
        XCTAssertEqual(try library.shelfItems(.text).count, 10)
        XCTAssertEqual(try library.shelfItems(.image).count, 3)
        XCTAssertEqual(try library.shelfItems(.link).count, 10)
    }

    func testASavedChoiceWinsAndAppliesAtLaunchAndFromSettings() throws {
        let f = try fixture(); defer { f.cleanup() }
        f.defaults.set(20, forKey: HistoryRetention.keepCountKey)
        let first = try store(f)
        for index in 0..<15 { _ = try first.captureText("choice synthetic \(index)"); f.date += 1 }
        XCTAssertEqual(try first.shelfItems(.text).count, 15)
        f.defaults.set(12, forKey: HistoryRetention.keepCountKey)
        XCTAssertEqual(try store(f).shelfItems(.text).count, 12, "checked at launch")
        let line = Line(defaults: f.defaults, inbox: f.inbox, now: { f.date }, breeze: false, moveToTrash: fixtureTrash(f.folder),
                        copyImage: { _ in }, copyText: { _ in }, library: try store(f), pruneOnLoad: false)
        line.setKeepCount(5)
        XCTAssertEqual(line.keepCount, 5)
        XCTAssertEqual(try XCTUnwrap(line.library).shelfItems(.text).count, 5)
        line.setKeepCount(7)
        XCTAssertEqual(line.keepCount, 5, "only the offered choices are saved")
    }
}
