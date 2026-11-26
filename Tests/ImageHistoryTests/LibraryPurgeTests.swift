import AppKit
#if !STANDALONE_TESTS
import XCTest
@testable import Tendedero
#endif

/// Expired copies and day-old Trash are deleted for good: rows, derived
/// rows and only the files the app itself made.
@MainActor final class LibraryPurgeTests: HistoryTestCase {
    private func store(_ f: SyntheticFixture) throws -> LibraryStore {
        try LibraryStore(defaults: f.defaults, inbox: f.inbox, now: { f.date }, moveToTrash: fixtureTrash(f.folder))
    }
    private func exists(_ path: String?) throws -> Bool { FileManager.default.fileExists(atPath: try XCTUnwrap(path)) }
    /// Rows naming this item in every table that refers to items.
    private func references(_ id: UUID, in library: LibraryStore) throws -> [String: Int64] {
        let db = try LibraryDatabase(url: library.databaseURL, readOnly: true, verify: false)
        var counts = [String: Int64]()
        for (table, column) in [("items", "id"), ("search_fts", "id"), ("text_identity", "item"), ("image_analysis", "item"), ("item_tags", "item"), ("item_collections", "item")] {
            counts[table] = try db.rows("SELECT count(*) AS n FROM \(table) WHERE \(column)=?", [.text(id.uuidString)]).first?["n"]?.number ?? -1
        }
        return counts
    }
    private let none: [String: Int64] = ["items": 0, "search_fts": 0, "text_identity": 0, "image_analysis": 0, "item_tags": 0, "item_collections": 0]

    func testExpiredClipboardCopyAndTextLoseTheirRowsAndAppFiles() throws {
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let library = try store(f)
        let image = try library.captureImage(try f.image())
        let text = try XCTUnwrap(library.captureText("purge synthetic text"))
        let textFile = try LibraryTransfer.materialize(text, store: library)
        XCTAssertTrue(try exists(image.path)); XCTAssertTrue(FileManager.default.fileExists(atPath: textFile.path))
        XCTAssertEqual(try references(text.id, in: library)["text_identity"], 1)
        f.date.addTimeInterval(31 * 86400); try library.prune()
        XCTAssertNil(try library.item(image.id)); XCTAssertNil(try library.item(text.id))
        XCTAssertEqual(try references(image.id, in: library), none)
        XCTAssertEqual(try references(text.id, in: library), none)
        XCTAssertFalse(try exists(image.path), "the app's clipboard copy is deleted")
        XCTAssertFalse(FileManager.default.fileExists(atPath: textFile.path), "the materialized text file is deleted")
        XCTAssertTrue(try library.query(LibraryQuery(scope: .trash)).isEmpty, "nothing waits in Trash")
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.folder.appendingPathComponent(".test-trash").path), "never the system Trash")
    }

    func testPinnedTaggedAndFolderedItemsAreNeverPurgedWhileLive() throws {
        let f = try SyntheticFixture(); defer { f.cleanup() }
        f.defaults.removeObject(forKey: HistoryRetention.keepCountKey)
        let library = try store(f)
        let pinned = try library.captureImage(try f.image())
        let tagged = try XCTUnwrap(library.captureText("tagged synthetic"))
        let foldered = try library.captureLink(try XCTUnwrap(URL(string: "https://example.com/foldered")))
        try library.pin([pinned.id]); try library.addTag("keep", to: [tagged.id])
        try library.assign([foldered.id], to: try library.createCollection("Kept"))
        f.date.addTimeInterval(90 * 86400)
        for index in 0..<12 { _ = try library.captureImage(try f.image()); _ = try library.captureText("filler \(index)"); f.date += 1 }
        try library.prune()
        for id in [pinned.id, tagged.id, foldered.id] { XCTAssertNil(try XCTUnwrap(library.item(id)).deletedAt) }
        XCTAssertTrue(try exists(pinned.path))
        XCTAssertEqual(try library.tags(for: tagged.id).map(\.name), ["keep"])
    }

    func testFilesOutsideTheStorageRootOrNotAppCopiesStayWhenTheRowIsPurged() throws {
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let library = try store(f)
        let external = try library.captureImage(try f.image(owned: false))
        // A screenshot macOS saved into the inbox folder: inside the storage
        // root, but not one of the app's "Clipboard <UUID>.png" copies.
        try FileManager.default.createDirectory(at: f.inbox, withIntermediateDirectories: true)
        let inboxShot = try f.image(owned: true, name: "Screenshot 2026-11-26 at 10.00.00.png")
        let screenshot = try library.captureImage(inboxShot)
        f.date.addTimeInterval(31 * 86400); try library.prune()
        XCTAssertNil(try library.item(external.id)); XCTAssertNil(try library.item(screenshot.id))
        XCTAssertTrue(try exists(external.path), "a file outside the storage root is never deleted")
        XCTAssertTrue(try exists(screenshot.path), "a screenshot in the inbox is not an app copy")
    }

    func testManualTrashSurvivesADayAndRestoresThenIsPurgedAfterIt() throws {
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let library = try store(f)
        let image = try library.captureImage(try f.image())
        let pinned = try XCTUnwrap(library.captureText("pinned then trashed")); try library.pin([pinned.id])
        try library.trashUndoably([image.id, pinned.id])
        f.date.addTimeInterval(LibraryStore.trashPurgeDelay - 60); try library.prune()
        XCTAssertNotNil(try XCTUnwrap(library.item(image.id)).deletedAt, "younger than a day: still in Trash")
        XCTAssertTrue(try exists(image.path))
        XCTAssertEqual(Set(try library.undoTrash()), Set([image.id, pinned.id]))
        XCTAssertNil(try XCTUnwrap(library.item(image.id)).deletedAt)

        try library.trash([image.id, pinned.id])
        f.date.addTimeInterval(LibraryStore.trashPurgeDelay + 60); try library.prune()
        XCTAssertNil(try library.item(image.id)); XCTAssertNil(try library.item(pinned.id), "a pinned item trashed by hand follows the Trash rule")
        XCTAssertEqual(try references(pinned.id, in: library), none)
        XCTAssertFalse(try exists(image.path))
    }

    func testTwoRowsSharingAPathKeepTheFileWhileOneIsLive() throws {
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let library = try store(f)
        let url = try f.image()
        let first = try library.captureImage(url)
        try library.trash([first.id])
        // The same file captured again while the first row is in Trash.
        let second = try library.captureImage(url)
        XCTAssertNotEqual(first.id, second.id); XCTAssertEqual(first.path, second.path)
        f.date.addTimeInterval(LibraryStore.trashPurgeDelay + 60); try library.prune()
        XCTAssertNil(try library.item(first.id)); XCTAssertNil(try XCTUnwrap(library.item(second.id)).deletedAt)
        XCTAssertTrue(try exists(second.path), "a live row still names the file")
        f.date.addTimeInterval(31 * 86400); try library.prune()
        XCTAssertNil(try library.item(second.id))
        XCTAssertFalse(try exists(second.path), "the last row is gone, so is the copy")
    }

    func testAMissingFileDoesNotStopThePurge() throws {
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let library = try store(f)
        let gone = try library.captureImage(try f.image()), kept = try library.captureImage(try f.image())
        try FileManager.default.removeItem(atPath: try XCTUnwrap(gone.path))
        f.date.addTimeInterval(31 * 86400)
        XCTAssertNoThrow(try library.prune())
        XCTAssertNil(try library.item(gone.id)); XCTAssertNil(try library.item(kept.id))
        XCTAssertFalse(try exists(kept.path))
    }
}
