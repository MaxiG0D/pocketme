import SwiftUI

enum SwipeSide: Sendable { case leading, trailing }

/// The one row that is currently swiped open; opening another closes it.
struct SwipeOpen: Equatable, Sendable {
    var id: UUID
    var side: SwipeSide
}

struct SwipeAction {
    var side: SwipeSide
    var symbol: String
    var color: Color
    var label: String
    var perform: () -> Void
}

/// All swipe layout lives here, in the row's own coordinates, so it cannot depend on the list,
/// split-view column or row inset that happens to contain the row.
enum SwipeGeometry {
    static let reveal: CGFloat = 84

    /// How far the row moves when it rests open. `inset` is the row's own side padding and `gap`
    /// the space left between its visible content and the button, so the button is `reveal` wide.
    static func openOffset(_ side: SwipeSide, inset: CGFloat, gap: CGFloat, edge: CGFloat = 0) -> CGFloat {
        let travel = reveal + edge - max(0, inset - gap)
        return side == .trailing ? -travel : travel
    }

    /// The button's frame in the row's coordinates: flush with the edge the row moved away from,
    /// starting exactly `gap` past the row's visible content and ending `edge` short of the screen side.
    static func buttonFrame(rowWidth: CGFloat, rowHeight: CGFloat, offset: CGFloat, inset: CGFloat, gap: CGFloat, edge: CGFloat = 0) -> CGRect {
        let overlap = max(0, inset - gap)
        if offset < 0 {
            let x = rowWidth + offset - overlap
            return CGRect(x: x, y: 0, width: rowWidth - edge - x, height: rowHeight)
        }
        if offset > 0 { return CGRect(x: edge, y: 0, width: offset + overlap - edge, height: rowHeight) }
        return .zero
    }

    /// Where a released drag comes to rest: open on a side that has an action once pulled past half, else closed.
    static func rest(for offset: CGFloat, actions: [SwipeAction], inset: CGFloat, gap: CGFloat, edge: CGFloat = 0) -> SwipeSide? {
        let half = abs(openOffset(.trailing, inset: inset, gap: gap, edge: edge)) / 2
        if offset <= -half, actions.contains(where: { $0.side == .trailing }) { return .trailing }
        if offset >= half, actions.contains(where: { $0.side == .leading }) { return .leading }
        return nil
    }

    static func clamp(_ offset: CGFloat, actions: [SwipeAction], inset: CGFloat, gap: CGFloat, edge: CGFloat = 0) -> CGFloat {
        let limit = abs(openOffset(.trailing, inset: inset, gap: gap, edge: edge)) * 1.25
        let lower = actions.contains { $0.side == .trailing } ? -limit : 0
        let upper = actions.contains { $0.side == .leading } ? limit : 0
        return min(upper, max(lower, offset))
    }
}

extension View {
    /// Swipe-to-reveal actions for a row, the same on iPhone, iPad, Duo and Mac. Give the row its own
    /// side padding (and zero list insets) and pass it as `inset`.
    func swipeReveal(id: UUID, open: Binding<SwipeOpen?>, actions: [SwipeAction], inset: CGFloat = 0, gap: CGFloat = 0, cornerRadius: CGFloat = 0, verticalInset: CGFloat = 0, edge: CGFloat = 0) -> some View {
        modifier(SwipeReveal(id: id, open: open, actions: actions, inset: inset, gap: gap, cornerRadius: cornerRadius, verticalInset: verticalInset, edge: edge))
    }
}

private struct SwipeReveal: ViewModifier {
    let id: UUID
    @Binding var open: SwipeOpen?
    let actions: [SwipeAction]
    let inset: CGFloat
    let gap: CGFloat
    let cornerRadius: CGFloat
    let verticalInset: CGFloat
    let edge: CGFloat
    @State private var live: CGFloat?
    @State private var horizontal: Bool?
    @State private var hover = false
    @State private var monitor: Any?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var resting: CGFloat {
        guard let open, open.id == id else { return 0 }
        return SwipeGeometry.openOffset(open.side, inset: inset, gap: gap, edge: edge)
    }
    private var offset: CGFloat { live ?? resting }

    func body(content: Content) -> some View {
        ZStack { content.offset(x: offset) }
            // Above the row, so the button can cover its empty side padding and sit `gap` from the content.
            .overlay { GeometryReader { geo in button(in: geo.size) } }
            #if os(iOS)
            .gesture(HorizontalPan(changed: drag, ended: release))
            #else
            .onHover { hover = $0 }
            .onAppear { monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { scroll($0) } }
            .onDisappear { if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil }
            #endif
            .accessibilityElement(children: .contain)
            .accessibilityActions { ForEach(actions.indices, id: \.self) { index in
                Button(actions[index].label) { actions[index].perform() }
            } }
    }

    @ViewBuilder private func button(in size: CGSize) -> some View {
        let side: SwipeSide = offset < 0 ? .trailing : .leading
        if offset != 0, let action = actions.first(where: { $0.side == side }) {
            let frame = SwipeGeometry.buttonFrame(rowWidth: size.width, rowHeight: size.height, offset: offset, inset: inset, gap: gap, edge: edge)
            Button {
                close()
                action.perform()
            } label: {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(action.color)
                    .overlay { Image(systemName: action.symbol).font(.system(size: 18, weight: .semibold)).foregroundStyle(.white) }
            }
            .buttonStyle(.plain).accessibilityLabel(action.label)
            .frame(width: max(0, frame.width), height: max(0, frame.height - verticalInset * 2))
            .position(x: frame.midX, y: frame.midY)
        }
    }

    private func close() { settle(nil) }

    private func settle(_ side: SwipeSide?) {
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) {
            live = nil
            open = side.map { SwipeOpen(id: id, side: $0) }
        }
    }

    private func release() {
        horizontal = nil
        settle(SwipeGeometry.rest(for: offset, actions: actions, inset: inset, gap: gap, edge: edge))
    }

    private func move(by delta: CGFloat) {
        live = SwipeGeometry.clamp((live ?? resting) + delta, actions: actions, inset: inset, gap: gap, edge: edge)
    }

    #if os(iOS)
    private func drag(_ translation: CGFloat) {
        live = SwipeGeometry.clamp(resting + translation, actions: actions, inset: inset, gap: gap, edge: edge)
    }
    #else
    /// Two-finger trackpad swipes arrive as scroll events, not drags.
    private func scroll(_ event: NSEvent) -> NSEvent? {
        guard event.hasPreciseScrollingDeltas else { return event }
        if event.phase == .began || event.phase == .mayBegin {
            horizontal = hover && abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)
            if horizontal != true, open != nil { close() }
        }
        guard horizontal == true else { return event }
        if event.phase == .ended || event.phase == .cancelled { release(); return nil }
        move(by: event.scrollingDeltaX)
        return nil
    }
    #endif
}

#if os(iOS)
/// A UIKit pan that only begins on a sideways drag. Taps never start it, so the list still selects the
/// row, and vertical drags fail it, so the list still scrolls. A SwiftUI DragGesture on a List row
/// claims the touch first and swallows the tap that should open the article.
private struct HorizontalPan: UIGestureRecognizerRepresentable {
    let changed: (CGFloat) -> Void
    let ended: () -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.delegate = context.coordinator
        return pan
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        switch recognizer.state {
        case .changed: changed(recognizer.translation(in: recognizer.view).x)
        case .ended, .cancelled: ended()
        default: break
        }
    }

    @MainActor final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard let pan = recognizer as? UIPanGestureRecognizer else { return false }
            let velocity = pan.velocity(in: pan.view)
            return abs(velocity.x) > abs(velocity.y) * 1.5
        }
    }
}
#endif
