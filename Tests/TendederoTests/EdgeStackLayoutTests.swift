#if !STANDALONE_TESTS
import XCTest
@testable import Tendedero

final class EdgeStackLayoutTests: XCTestCase {
    private let accuracy: CGFloat = 0.0001

    func testPanelFitsFiveSlotsWithMarginAndScreenInset() {
        let size = EdgeStackLayout.panelSize(scale: 1)
        XCTAssertEqual(size.width, 18 + 160 + 10, accuracy: accuracy)
        XCTAssertEqual(size.height, 5 * 106 + 4 * 8 + 2 * 18, accuracy: accuracy)
    }

    func testScaleKeepsThePreferenceAndShrinksOnlyForShortScreens() {
        XCTAssertEqual(EdgeStackLayout.scale(preferred: 1.35, availableHeight: 2000), 1.35, accuracy: accuracy)
        let short = EdgeStackLayout.scale(preferred: 1, availableHeight: 400)
        XCTAssertLessThan(short, 1)
        XCTAssertEqual(EdgeStackLayout.panelSize(scale: short).height, 400, accuracy: 0.001)
        XCTAssertEqual(EdgeStackLayout.scale(preferred: 1, availableHeight: 50), 0.5, accuracy: accuracy)
        XCTAssertEqual(EdgeStackLayout.scale(preferred: 1, availableHeight: .infinity), 1, accuracy: accuracy)
    }

    func testExactlyTheNewestFiveCardsAreFullyVisibleAtTheTop() {
        let viewportTop = EdgeStackLayout.margin
        let viewportBottom = viewportTop + EdgeStackLayout.viewportHeight(scale: 1)
        let fullyVisible = (0..<8).filter { index in
            let frame = EdgeStackLayout.cardFrame(index: index, image: nil, offset: 0, scale: 1)
            return frame.minY >= viewportTop - accuracy && frame.maxY <= viewportBottom + accuracy
        }
        XCTAssertEqual(fullyVisible, [0, 1, 2, 3, 4])
    }

    func testScrollingOneCardShowsTheNextOlderFive() {
        let pitch = EdgeStackLayout.pitch(scale: 1)
        let viewportTop = EdgeStackLayout.margin
        let viewportBottom = viewportTop + EdgeStackLayout.viewportHeight(scale: 1)
        let fullyVisible = (0..<8).filter { index in
            let frame = EdgeStackLayout.cardFrame(index: index, image: nil, offset: pitch, scale: 1)
            return frame.minY >= viewportTop - accuracy && frame.maxY <= viewportBottom + accuracy
        }
        XCTAssertEqual(fullyVisible, [1, 2, 3, 4, 5])
    }

    func testOffsetMapsStripCardsToStackRowsAndClamps() {
        let spacing: CGFloat = 174, pitch = EdgeStackLayout.pitch(scale: 1)
        XCTAssertEqual(EdgeStackLayout.offset(lineOffset: 2 * spacing, spacing: spacing, count: 12, scale: 1), 2 * pitch, accuracy: accuracy)
        // Never past the last card, never above the first.
        XCTAssertEqual(EdgeStackLayout.offset(lineOffset: 100 * spacing, spacing: spacing, count: 12, scale: 1), 7 * pitch, accuracy: accuracy)
        XCTAssertEqual(EdgeStackLayout.offset(lineOffset: -50, spacing: spacing, count: 12, scale: 1), 0)
        // Five cards or fewer do not scroll.
        XCTAssertEqual(EdgeStackLayout.offset(lineOffset: 3 * spacing, spacing: spacing, count: 5, scale: 1), 0)
        XCTAssertEqual(EdgeStackLayout.offset(lineOffset: .nan, spacing: spacing, count: 12, scale: 1), 0)
        XCTAssertEqual(EdgeStackLayout.maximumOffset(count: 3, scale: 1), 0)
    }

    /// The model clamps its own offset with the viewport width the stack
    /// gives it; that limit must be exactly "all but the last five cards".
    func testModelViewportWidthMakesTheModelStopAtTheLastFiveCards() {
        let width = EdgeStackLayout.lineViewportWidth(spacing: Layout.spacing, edgePadding: Layout.edgePadding)
        for count in [6, 12, 40] {
            XCTAssertEqual(Layout.maximumOffset(count: count, width: width), CGFloat(count - 5) * Layout.spacing, accuracy: 0.001)
        }
        XCTAssertEqual(Layout.maximumOffset(count: 4, width: width), 0)
    }

    /// The model only keeps thumbnails for its own visible range. That range
    /// must cover every card the stack builds, or a card would show a placeholder.
    func testModelThumbnailWindowCoversEveryBuiltCard() {
        let width = EdgeStackLayout.lineViewportWidth(spacing: Layout.spacing, edgePadding: Layout.edgePadding)
        let count = 30
        for card in 0...(count - 5) {
            let lineOffset = CGFloat(card) * Layout.spacing
            let stackOffset = EdgeStackLayout.offset(lineOffset: lineOffset, spacing: Layout.spacing, count: count, scale: 1)
            let built = EdgeStackLayout.visibleRange(count: count, offset: stackOffset, scale: 1)
            let thumbnails = Layout.visibleRange(count: count, width: width, offset: lineOffset)
            XCTAssertTrue(thumbnails.contains(built.lowerBound) && thumbnails.contains(built.upperBound - 1),
                          "card \(card): built \(built) thumbnails \(thumbnails)")
        }
    }

    func testVisibleRangeBuildsOneCardBufferAndHandlesSmallCounts() {
        let pitch = EdgeStackLayout.pitch(scale: 1)
        XCTAssertEqual(EdgeStackLayout.visibleRange(count: 0, offset: 0, scale: 1), 0..<0)
        XCTAssertEqual(EdgeStackLayout.visibleRange(count: 3, offset: 0, scale: 1), 0..<3)
        XCTAssertEqual(EdgeStackLayout.visibleRange(count: 20, offset: 0, scale: 1), 0..<6)
        XCTAssertEqual(EdgeStackLayout.visibleRange(count: 20, offset: 3 * pitch, scale: 1), 2..<9)
        XCTAssertEqual(EdgeStackLayout.visibleRange(count: 20, offset: 15 * pitch, scale: 1), 14..<20)
    }

    func testCardsFitTheSlotAndHugTheScreenEdge() {
        let wide = EdgeStackLayout.cardSize(for: CGSize(width: 1600, height: 900), scale: 1)
        XCTAssertEqual(wide.width, 160, accuracy: accuracy)
        XCTAssertEqual(wide.height, 90, accuracy: accuracy)
        let tall = EdgeStackLayout.cardSize(for: CGSize(width: 900, height: 1600), scale: 1)
        XCTAssertEqual(tall.height, 106, accuracy: accuracy)
        XCTAssertEqual(tall.width, 900 * 106 / 1600, accuracy: accuracy)
        XCTAssertEqual(EdgeStackLayout.cardSize(for: nil, scale: 1), EdgeStackLayout.slot(scale: 1))

        let frame = EdgeStackLayout.cardFrame(index: 1, image: CGSize(width: 1600, height: 900), offset: 0, scale: 1)
        XCTAssertEqual(frame.maxX, EdgeStackLayout.margin + 160, accuracy: accuracy)
        let slotTop = EdgeStackLayout.slotTop(index: 1, offset: 0, scale: 1)
        XCTAssertEqual(frame.midY, slotTop + 106 / 2, accuracy: accuracy)
    }

    @MainActor
    func testCardsKeepNewestFirstAndSkipFallingOnes() {
        var items = (0..<4).map { Pegged(url: URL(fileURLWithPath: "/tmp/stack-\($0).png"), thumb: nil) }
        items[1].falling = true
        let cards = EdgeStackLayout.cards(from: items)
        XCTAssertEqual(cards.map(\.id), [items[0].id, items[2].id, items[3].id])
    }
}
#endif
