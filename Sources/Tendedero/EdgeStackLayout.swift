import CoreGraphics
import Foundation

/// Geometry of the vertical image stack at the right edge of the screen.
///
/// The stack is a second rendering of the image shelf's existing state: it
/// reads `Line.displayItems` and `Line.scrollOffset`, and it drives that same
/// offset when scrolled. The strip measures its offset in strip points (one
/// card is `Layout.spacing` wide); the stack shows one card per `pitch` points
/// vertically. The functions here translate between the two so the model's
/// thumbnail window, selection scrolling and "new capture scrolls to the
/// start" behaviour keep working without changes to `Line`.
///
/// Everything here is pure so it can be unit tested.
enum EdgeStackLayout {
    /// How many cards are visible at once; older ones are reached by scrolling.
    static let visibleCount = 5
    /// The stack's slot at scale 1. Each image is fitted inside it, keeping
    /// its proportions, and aligned to the trailing (screen) edge.
    static let baseSlot = CGSize(width: 160, height: 106)
    /// Vertical space between two cards.
    static let gap: CGFloat = 8
    /// Room around the cards for their shadow and hover growth.
    static let margin: CGFloat = 18
    /// Distance between the cards and the right edge of the screen.
    static let screenInset: CGFloat = 10
    /// How long a new image keeps the stack in view before it slides away
    /// again (the pointer resting over it keeps it longer).
    static let peekDuration: TimeInterval = 3.5
    /// The corner radius of a card.
    static let cornerRadius: CGFloat = 10

    // MARK: Size

    static func slot(scale: CGFloat) -> CGSize {
        CGSize(width: baseSlot.width * scale, height: baseSlot.height * scale)
    }

    static func pitch(scale: CGFloat) -> CGFloat { slot(scale: scale).height + gap }

    /// The height of the area that shows `visibleCount` cards.
    static func viewportHeight(scale: CGFloat) -> CGFloat {
        CGFloat(visibleCount) * slot(scale: scale).height + CGFloat(visibleCount - 1) * gap
    }

    /// The panel's size: the viewport plus the shadow margin, and the slot
    /// plus margin on the leading side and the screen inset on the trailing side.
    static func panelSize(scale: CGFloat) -> CGSize {
        CGSize(width: margin + slot(scale: scale).width + screenInset,
               height: viewportHeight(scale: scale) + margin * 2)
    }

    /// The user's size setting, shrunk when the screen is too short to show
    /// all visible cards at that size. Never below a legible minimum.
    static func scale(preferred: CGFloat, availableHeight: CGFloat) -> CGFloat {
        guard preferred.isFinite, preferred > 0 else { return 1 }
        guard availableHeight.isFinite, availableHeight > 0 else { return preferred }
        let fixed = CGFloat(visibleCount - 1) * gap + margin * 2
        let fit = (availableHeight - fixed) / (CGFloat(visibleCount) * baseSlot.height)
        return max(0.5, min(preferred, fit))
    }

    /// The image fitted inside the slot, keeping its proportions.
    static func cardSize(for image: CGSize?, scale: CGFloat) -> CGSize {
        let box = slot(scale: scale)
        guard let image, image.width > 0, image.height > 0 else { return box }
        let factor = min(box.width / image.width, box.height / image.height)
        return CGSize(width: image.width * factor, height: image.height * factor)
    }

    // MARK: Scrolling

    /// The furthest the stack can scroll, in stack points.
    static func maximumOffset(count: Int, scale: CGFloat) -> CGFloat {
        CGFloat(max(0, count - visibleCount)) * pitch(scale: scale)
    }

    /// The viewport width the strip model is given while the stack is shown.
    /// With it, the strip's maximum offset is exactly `count - visibleCount`
    /// cards, and its thumbnail window covers the stack's visible cards plus a
    /// one-card buffer on each side.
    static func lineViewportWidth(spacing: CGFloat, edgePadding: CGFloat) -> CGFloat {
        CGFloat(visibleCount) * spacing + edgePadding
    }

    /// The model's offset (strip points) as a stack offset, clamped to the
    /// stack's own range so a card being removed never leaves a hole at the end.
    static func offset(lineOffset: CGFloat, spacing: CGFloat, count: Int, scale: CGFloat) -> CGFloat {
        guard lineOffset.isFinite, spacing > 0 else { return 0 }
        let mapped = lineOffset / spacing * pitch(scale: scale)
        return max(0, min(maximumOffset(count: count, scale: scale), mapped))
    }

    /// The cards to build: the visible ones and one more above and below, so a
    /// scroll never shows an empty slot before the next card is built.
    static func visibleRange(count: Int, offset: CGFloat, scale: CGFloat) -> Range<Int> {
        guard count > 0 else { return 0..<0 }
        let step = pitch(scale: scale)
        let clamped = max(0, offset)
        let first = max(0, Int(floor(clamped / step)) - 1)
        let last = min(count, Int(ceil((clamped + viewportHeight(scale: scale)) / step)) + 1)
        return min(first, last)..<last
    }

    /// The top of a slot in panel coordinates (origin top left).
    static func slotTop(index: Int, offset: CGFloat, scale: CGFloat) -> CGFloat {
        margin + CGFloat(index) * pitch(scale: scale) - offset
    }

    /// The frame of a card in panel coordinates (origin top left): its slot's
    /// row, vertically centred in it and aligned to the trailing edge.
    static func cardFrame(index: Int, image: CGSize?, offset: CGFloat, scale: CGFloat) -> CGRect {
        let box = slot(scale: scale)
        let size = cardSize(for: image, scale: scale)
        let top = slotTop(index: index, offset: offset, scale: scale) + (box.height - size.height) / 2
        let trailing = margin + box.width
        return CGRect(x: trailing - size.width, y: top, width: size.width, height: size.height)
    }

    // MARK: Content

    /// What the stack shows: images on the shelf, newest first, without the
    /// ones already on their way out.
    static func cards(from items: [Pegged]) -> [Pegged] {
        items.filter { !$0.falling }
    }
}
