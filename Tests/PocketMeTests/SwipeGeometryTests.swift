import CoreGraphics
import Testing
@testable import PocketMe

/// Guards the swipe button against drifting from its row, whatever list or column holds the row.
struct SwipeGeometryTests {
    private let widths: [CGFloat] = [320, 390, 420, 732]
    private let layouts: [(inset: CGFloat, gap: CGFloat)] = [(20, 12), (0, 0), (20, 0)]

    @Test func trailingButtonIsFlushWithRowEdgeAndGapFromContent() {
        for width in widths {
            for layout in layouts {
                let offset = SwipeGeometry.openOffset(.trailing, inset: layout.inset, gap: layout.gap)
                let frame = SwipeGeometry.buttonFrame(rowWidth: width, rowHeight: 100, offset: offset, inset: layout.inset, gap: layout.gap)
                let contentEdge = width - layout.inset + offset
                #expect(frame.maxX == width)
                #expect(frame.minX - contentEdge == layout.gap)
                #expect(frame.width == SwipeGeometry.reveal)
            }
        }
    }

    @Test func leadingButtonMirrorsTrailing() {
        for width in widths {
            for layout in layouts {
                let offset = SwipeGeometry.openOffset(.leading, inset: layout.inset, gap: layout.gap)
                let frame = SwipeGeometry.buttonFrame(rowWidth: width, rowHeight: 100, offset: offset, inset: layout.inset, gap: layout.gap)
                let contentEdge = layout.inset + offset
                #expect(frame.minX == 0)
                #expect(contentEdge - frame.maxX == layout.gap)
                #expect(frame.width == SwipeGeometry.reveal)
            }
        }
    }

    @Test func gapHoldsWhileDragging() {
        for offset in stride(from: CGFloat(-80), through: -1, by: 7) {
            let frame = SwipeGeometry.buttonFrame(rowWidth: 390, rowHeight: 100, offset: offset, inset: 20, gap: 12)
            #expect(frame.maxX == 390)
            #expect(frame.minX - (390 - 20 + offset) == 12)
        }
    }

    @Test func closedRowHasNoButton() {
        #expect(SwipeGeometry.buttonFrame(rowWidth: 390, rowHeight: 100, offset: 0, inset: 20, gap: 12) == .zero)
    }
}
