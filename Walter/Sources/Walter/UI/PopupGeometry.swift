import Foundation

/// Pure geometry, independent of AppKit's live screen state.
enum PopupGeometry {
    static func visibleFrame(pointer: CGPoint, screens: [(CGRect, CGRect)], fallback: CGRect?) -> CGRect {
        screens.first(where: { $0.0.contains(pointer) })?.1
            ?? fallback ?? screens.first?.1 ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
    }

    /// Compute the final size AND origin before touching the window. Resizing
    /// first and repositioning afterward would produce an intermediate frame
    /// with the wrong top edge, especially on the empty-to-results transition.
    static func fittedFrame(width: CGFloat, height: CGFloat, in visible: CGRect) -> CGRect {
        upperCentered(size: CGSize(width: min(width, visible.width * 0.95),
                                   height: min(height, visible.height * 0.9)), in: visible)
    }

    /// Horizontally centered, with the top edge 30% down the visible screen.
    /// Keep that anchor as results grow; shift up only to avoid the bottom edge.
    static func upperCentered(size: CGSize, in visible: CGRect) -> CGRect {
        let top = visible.maxY - visible.height * 0.3
        return CGRect(x: visible.midX - size.width / 2,
                      y: max(visible.minY, top - size.height),
                      width: size.width, height: size.height)
    }
}
