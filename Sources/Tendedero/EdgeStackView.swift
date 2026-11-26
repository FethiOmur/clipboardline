import SwiftUI

/// The image shelf as a vertical stack at the right edge of the screen: plain
/// rounded thumbnails with a soft shadow, newest at the top, in the spirit of
/// the system's screenshot thumbnail. Text and link history are not shown
/// here; they stay in the Library.
///
/// Positions come from `EdgeStackLayout`, so the panel's pass-through hit
/// testing (via `HitRectsKey`) and the model's thumbnail window agree with
/// what is drawn. Nothing here animates while the stack is idle: the only
/// animations are short, value-triggered transitions (insertion, removal,
/// hover, copy feedback), and none of them run with Reduce Motion on.
struct EdgeStackView: View {
    @ObservedObject var line: Line
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let scale = EdgeStackLayout.scale(preferred: line.size.scale, availableHeight: geo.size.height)
            let cards = EdgeStackLayout.cards(from: line.displayItems)
            let offset = EdgeStackLayout.offset(lineOffset: line.scrollOffset, spacing: Layout.spacing,
                                                count: cards.count, scale: scale)
            let range = EdgeStackLayout.visibleRange(count: cards.count, offset: offset, scale: scale)
            ZStack(alignment: .topLeading) {
                if cards.isEmpty {
                    emptyState(scale: scale)
                }
                ForEach(range.map { (index: $0, item: cards[$0]) }, id: \.item.id) { index, item in
                    let frame = EdgeStackLayout.cardFrame(index: index, image: item.thumb?.size,
                                                          offset: offset, scale: scale)
                    EdgeStackCard(item: item, line: line, size: frame.size)
                        .frame(width: frame.width, height: frame.height)
                        .position(x: frame.midX, y: frame.midY)
                        .transition(reduceMotion ? .identity
                                    : .opacity.combined(with: .scale(scale: 0.92, anchor: .trailing)))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            // Exactly `visibleCount` cards show. The panel is a little taller
            // than that for shadows, and without this the next card's edge
            // would peek into that margin.
            .mask(Rectangle().padding(.vertical, EdgeStackLayout.clipInset))
            // One short spring when cards are added or removed, then still.
            .animation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.86),
                       value: cards.map(\.id))
        }
        .onPreferenceChange(HitRectsKey.self) { line.hitRects = $0; line.shelfHitGeometryUpdateCount += 1 }
    }

    private func emptyState(scale: CGFloat) -> some View {
        let filtered = line.shelfSearch?.isActive(for: .image) == true || line.favoritesOnly
        return Text(filtered ? L("No matching items") : L("Take a screenshot and it will hang here"))
            .font(.system(size: 12))
            .multilineTextAlignment(.trailing)
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: EdgeStackLayout.cornerRadius, style: .continuous))
            .frame(width: EdgeStackLayout.slot(scale: scale).width, alignment: .trailing)
            .padding(.top, EdgeStackLayout.margin)
            .padding(.leading, EdgeStackLayout.margin)
            .allowsHitTesting(false)
    }
}

/// One thumbnail. The AppKit `GrabArea` on top handles every pointer action,
/// exactly as on the strip: click copies, drag gives the file to another app
/// or Finder, the top left corner removes the card, the top right corner pins
/// it, double click opens, press and hold opens Markup, force click opens
/// Quick Look, and right click shows the card's menu.
private struct EdgeStackCard: View {
    let item: Pegged
    @ObservedObject var line: Line
    let size: CGSize
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var copied: Bool { line.copiedID == item.id }
    private var dragging: Bool { line.draggingID == item.id }
    private var pressed: Bool { line.pressedID == item.id }
    /// A ring only for a multiple selection (command or shift click), where
    /// it tells which cards a drag or a copy will take. A single click on the
    /// stack copies and needs no lasting mark.
    private var markedInSelection: Bool { line.selectedIDs.count > 1 && line.selectedIDs.contains(item.id) }
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: EdgeStackLayout.cornerRadius, style: .continuous) }

    var body: some View {
        thumbnail
            .clipShape(shape)
            .overlay(shape.strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
            .overlay {
                if item.isRecording {
                    Image(systemName: "play.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.primary)
                        .frame(width: 26, height: 26)
                        .background(.regularMaterial, in: Circle())
                        .allowsHitTesting(false)
                }
            }
            .overlay {
                if markedInSelection {
                    shape.strokeBorder(Color.accentColor, lineWidth: 2.5).allowsHitTesting(false)
                }
            }
            .overlay(alignment: .topLeading) {
                // Drawn here, clicked through GrabView's corner handling.
                cornerButton(item.managedCopy ? "xmark" : "eye.slash")
                    .opacity(hovering && !dragging ? 1 : 0)
            }
            .overlay(alignment: .topTrailing) {
                cornerButton(item.pinned ? "pin.fill" : "pin", tint: item.pinned ? .accentColor : .primary)
                    .opacity((hovering || item.pinned) && !dragging ? 1 : 0)
            }
            .overlay {
                if copied {
                    Label(L("Copied"), systemImage: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .fixedSize()
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(.regularMaterial, in: Capsule())
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .shadow(color: .black.opacity(hovering ? 0.32 : 0.22), radius: hovering ? 10 : 7, y: hovering ? 4 : 2)
            .scaleEffect(pressed ? 0.97 : (hovering ? 1.03 : 1), anchor: .trailing)
            .opacity(dragging ? 0.45 : 1)
            // Unscaled, like on the strip: AppKit hit testing ignores SwiftUI's scale.
            .overlay(GrabArea(item: item, line: line))
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: hovering)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: pressed)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: copied)
            .onHover { hovering = $0 }
            .onAppear { _ = line.consumeArrival(item.id) }
            .background(
                GeometryReader { g in
                    Color.clear.preference(key: HitRectsKey.self, value: [item.id: g.frame(in: .global)])
                }
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(item.title ?? item.url.deletingPathExtension().lastPathComponent)
            .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder private var thumbnail: some View {
        if let thumb = item.thumb {
            Image(nsImage: thumb)
                .resizable()
                .interpolation(.high)
                .frame(width: size.width, height: size.height)
        } else {
            // The thumbnail is still decoding: a quiet placeholder of the slot.
            Rectangle().fill(.regularMaterial)
                .frame(width: size.width, height: size.height)
        }
    }

    private func cornerButton(_ symbol: String, tint: Color = .primary) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(tint)
            .frame(width: 18, height: 18)
            .background(.regularMaterial, in: Circle())
            .overlay(Circle().strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
            .padding(4)
            .allowsHitTesting(false)
    }
}
