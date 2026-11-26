import XCTest
@testable import Tendedero

/// Periodic work an idle app does; each wake has to earn its place.
final class IdleCostTests: XCTestCase {
    func testLibraryCatchUpScanIsRare() {
        // It used to run every two minutes and showed up as CPU in an idle
        // app. New images are scanned as they arrive and opening the Library
        // catches up, so the timer only backs that up.
        XCTAssertGreaterThanOrEqual(LibraryImageSearch.catchUpInterval, 15 * 60)
    }

    func testWatchedFolderIdentityPollIsRareWhileItsParentIsWatched() {
        XCTAssertGreaterThanOrEqual(ScreenshotWatcher.identityPollWithParentWatch, 30)
    }
}
