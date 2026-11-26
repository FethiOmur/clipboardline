#if !STANDALONE_TESTS
import XCTest
@testable import Tendedero

final class DoubleDotDetectorTests: XCTestCase {
    /// Feeds (isDot, time) presses and returns the times the gesture fired.
    private func fired(_ presses: [(Bool, TimeInterval)]) -> [TimeInterval] {
        var detector = DoubleDotDetector()
        return presses.filter { detector.keyDown(isDot: $0.0, at: $0.1) }.map(\.1)
    }

    func testTwoQuickPeriodsAfterAPauseFire() {
        XCTAssertEqual(fired([(true, 10.0), (true, 10.2)]), [10.2])
    }

    func testTwoSlowPeriodsDoNotFire() {
        XCTAssertEqual(fired([(true, 10.0), (true, 10.4)]), [])
    }

    func testAKeyBetweenThePeriodsCancels() {
        XCTAssertEqual(fired([(true, 10.0), (false, 10.1), (true, 10.2)]), [])
    }

    func testPeriodsTypedInTheFlowOfTextDoNotFire() {
        // "cd .." typed at speed: c, d, space, period, period.
        XCTAssertEqual(fired([(false, 10.0), (false, 10.1), (false, 10.2), (true, 10.3), (true, 10.4)]), [])
    }

    func testPeriodsAfterTypingStoppedFire() {
        XCTAssertEqual(fired([(false, 10.0), (true, 10.3), (true, 10.45)]), [10.45])
    }

    func testARunOfPeriodsFiresOnce() {
        XCTAssertEqual(fired([(true, 10.0), (true, 10.1), (true, 10.2), (true, 10.3), (true, 10.4)]), [10.1])
    }

    func testASecondGestureAfterAPauseFiresAgain() {
        XCTAssertEqual(fired([(true, 10.0), (true, 10.1), (true, 11.0), (true, 11.1)]), [10.1, 11.1])
    }

    func testResetForgetsTheFirstPeriod() {
        var detector = DoubleDotDetector()
        XCTAssertFalse(detector.keyDown(isDot: true, at: 10.0))
        detector.reset()
        XCTAssertFalse(detector.keyDown(isDot: true, at: 10.1))
    }
}

final class MenuBarRevealDefaultTests: XCTestCase {
    /// Uses the test runner's own defaults domain and puts it back.
    @MainActor
    func testMenuBarRevealStartsOffAndKeepsASavedChoice() {
        let defaults = UserDefaults.standard
        let saved = defaults.object(forKey: "menuBarRevealOff")
        defer { if let saved { defaults.set(saved, forKey: "menuBarRevealOff") } else { defaults.removeObject(forKey: "menuBarRevealOff") } }

        defaults.removeObject(forKey: "menuBarRevealOff")
        XCTAssertFalse(AppDelegate.opensFromMenuBar)
        AppDelegate.opensFromMenuBar = true
        XCTAssertTrue(AppDelegate.opensFromMenuBar)
        AppDelegate.opensFromMenuBar = false
        XCTAssertFalse(AppDelegate.opensFromMenuBar)
    }

    @MainActor
    func testHangingCopiedImagesStartsOnAndKeepsASavedChoice() {
        let defaults = UserDefaults.standard
        let saved = defaults.object(forKey: "clipboardEnabled")
        defer { if let saved { defaults.set(saved, forKey: "clipboardEnabled") } else { defaults.removeObject(forKey: "clipboardEnabled") } }

        defaults.removeObject(forKey: "clipboardEnabled")
        XCTAssertTrue(ClipboardWatcher.isEnabled)
        ClipboardWatcher.isEnabled = false
        XCTAssertFalse(ClipboardWatcher.isEnabled)
    }

    @MainActor
    func testImagesAreNotReadForSearchUnlessSwitchedOn() {
        let defaults = UserDefaults.standard
        let saved = defaults.object(forKey: "imageSearchIndexing")
        defer { if let saved { defaults.set(saved, forKey: "imageSearchIndexing") } else { defaults.removeObject(forKey: "imageSearchIndexing") } }

        defaults.removeObject(forKey: "imageSearchIndexing")
        XCTAssertFalse(LibraryImageSearch.isEnabled)
        LibraryImageSearch.isEnabled = true
        XCTAssertTrue(LibraryImageSearch.isEnabled)
    }

    func testShowingOverFullScreenStartsOnAndKeepsASavedChoice() {
        let defaults = UserDefaults.standard
        let saved = defaults.object(forKey: "showOverFullScreen")
        defer { if let saved { defaults.set(saved, forKey: "showOverFullScreen") } else { defaults.removeObject(forKey: "showOverFullScreen") } }

        defaults.removeObject(forKey: "showOverFullScreen")
        XCTAssertTrue(FullScreen.showLineOver)
        FullScreen.showLineOver = false
        XCTAssertFalse(FullScreen.showLineOver)
        FullScreen.showLineOver = true
        XCTAssertTrue(FullScreen.showLineOver)
    }
}
#endif
