import Foundation
import Testing
@testable import Walter

struct PopupGeometryTests {
    @Test func pointerScreenUpperPlacementAndResize() {
        let left = CGRect(x: -1600, y: 0, width: 1600, height: 1000)
        let leftVisible = CGRect(x: -1600, y: 40, width: 1600, height: 935)
        let right = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let selected = PopupGeometry.visibleFrame(pointer: CGPoint(x: -300, y: 800), screens: [(left, leftVisible), (right, right)], fallback: right)
        #expect(selected == leftVisible)
        let expectedTop = selected.maxY - selected.height * 0.3
        for height in [72.0, 300.0, 600.0] {
            let frame = PopupGeometry.upperCentered(size: CGSize(width: 780, height: height), in: selected)
            #expect(frame.midX == selected.midX)
            #expect(frame.maxY == expectedTop)
            #expect(selected.contains(frame))
        }
        let tall = PopupGeometry.upperCentered(size: CGSize(width: 780, height: 700), in: selected)
        #expect(tall.midX == selected.midX)
        #expect(tall.minY == selected.minY)
        #expect(selected.contains(tall))
    }
    @Test func emptyToResultsAndBackComputesFinalFrameDirectly() {
        let visible = CGRect(x: -1440, y: 40, width: 1440, height: 900)
        let top = visible.maxY - visible.height * 0.3
        let empty = PopupGeometry.fittedFrame(width: 780, height: 72, in: visible)
        let populated = PopupGeometry.fittedFrame(width: 780, height: 500, in: visible)
        #expect(empty.maxY == top)
        #expect(populated.maxY == top)
        #expect(empty.midX == populated.midX)
        #expect(populated.height == 500)
        #expect(populated.minY == top - 500) // No resize-at-the-old-origin step.
        #expect(PopupGeometry.fittedFrame(width: 780, height: 72, in: visible) == empty)
        let oversized = PopupGeometry.fittedFrame(width: 2000, height: 2000, in: visible)
        #expect(oversized.width == visible.width * 0.95)
        #expect(oversized.height == visible.height * 0.9)
        #expect(oversized.minY == visible.minY)
        #expect(visible.contains(oversized))
    }

    @Test func missingScreenFallback() {
        let fallback = CGRect(x: 100, y: 100, width: 1200, height: 800)
        #expect(PopupGeometry.visibleFrame(pointer: .zero, screens: [], fallback: fallback) == fallback)
        #expect(PopupGeometry.visibleFrame(pointer: .zero, screens: [], fallback: nil).size == CGSize(width: 1440, height: 900))
    }
}
