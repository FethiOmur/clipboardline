#if !STANDALONE_TESTS
import Carbon
import XCTest
@testable import Tendedero

@MainActor
final class RegionTextShortcutTests: XCTestCase {
    func testDefaultIsCommandShift2AndOffStaysOff() throws {
        let fixture = try SyntheticFixture(); defer { fixture.cleanup() }
        let line = fixture.line()
        XCTAssertEqual(line.regionTextShortcut, KeyShortcut(keyCode: kVK_ANSI_X, modifiers: optionKey | shiftKey, keyLabel: "X"))
        line.saveRegionTextShortcut(nil)
        XCTAssertNil(line.regionTextShortcut)
        XCTAssertNil(fixture.line().regionTextShortcut)
        let custom = KeyShortcut(keyCode: kVK_ANSI_3, modifiers: cmdKey | optionKey, keyLabel: "3")
        line.saveRegionTextShortcut(custom)
        XCTAssertEqual(fixture.line().regionTextShortcut, custom)
    }
}
#endif
