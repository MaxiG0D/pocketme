import CoreGraphics
import Testing
@testable import PocketMe

/// Guards the swipe button against drifting from its row, whatever list or column holds the row.
struct SwipeGeometryTests {
    private let widths: [CGFloat] = [320, 390, 420, 732]
    private let layouts: [(inset: CGFloat, gap: CGFloat, edge: CGFloat)] = [(20, 12, 12), (0, 0, 0), (20, 0, 8)]

    @Test func trailingButtonIsFlushWithRowEdgeAndGapFromContent() {
        for width in widths {
            for layout in layouts {
                let offset = SwipeGeometry.openOffset(.trailing, inset: layout.inset, gap: layout.gap, edge: layout.edge)
                let frame = SwipeGeometry.buttonFrame(rowWidth: width, rowHeight: 100, offset: offset, inset: layout.inset, gap: layout.gap, edge: layout.edge)
                let contentEdge = width - layout.inset + offset
                #expect(frame.maxX == width - layout.edge)
                #expect(frame.minX - contentEdge == layout.gap)
                #expect(frame.width == SwipeGeometry.reveal)
            }
        }
    }

    @Test func leadingButtonMirrorsTrailing() {
        for width in widths {
            for layout in layouts {
                let offset = SwipeGeometry.openOffset(.leading, inset: layout.inset, gap: layout.gap, edge: layout.edge)
                let frame = SwipeGeometry.buttonFrame(rowWidth: width, rowHeight: 100, offset: offset, inset: layout.inset, gap: layout.gap, edge: layout.edge)
                let contentEdge = layout.inset + offset
                #expect(frame.minX == layout.edge)
                #expect(contentEdge - frame.maxX == layout.gap)
                #expect(frame.width == SwipeGeometry.reveal)
            }
        }
    }

    @Test func gapHoldsWhileDragging() {
        // Closer to closed than the screen-edge margin plus the gap, the button has no width left to show.
        for offset in stride(from: CGFloat(-80), through: -8, by: 7) {
            let frame = SwipeGeometry.buttonFrame(rowWidth: 390, rowHeight: 100, offset: offset, inset: 20, gap: 12, edge: 12)
            let contentEdge: CGFloat = 390 - 20 + offset
            #expect(frame.maxX == CGFloat(378))
            #expect(frame.minX - contentEdge == CGFloat(12))
        }
    }

    @Test func closedRowHasNoButton() {
        #expect(SwipeGeometry.buttonFrame(rowWidth: 390, rowHeight: 100, offset: 0, inset: 20, gap: 12) == .zero)
    }
}
