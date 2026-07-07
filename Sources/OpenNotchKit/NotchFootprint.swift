import CoreGraphics

/// Pure geometry for the static-window animation substrate: the panel window
/// never resizes; only the rendered shape's "footprint" changes per phase.
public enum NotchFootprint {
    public static func size(phase: NotchPhase, showAmbient: Bool,
                            notchSize: CGSize, ambientSize: CGSize,
                            expandedSize: CGSize) -> CGSize {
        switch phase {
        case .expanded, .pinned: expandedSize
        case .collapsed: showAmbient ? ambientSize : notchSize
        case .hidden: notchSize   // window is ordered out; keep a sane morph origin
        }
    }

    /// Where the footprint sits inside the view (top-center), in view coordinates.
    public static func hitRect(footprint: CGSize, bounds: CGRect, flipped: Bool) -> CGRect {
        CGRect(x: bounds.midX - footprint.width / 2,
               y: flipped ? bounds.minY : bounds.maxY - footprint.height,
               width: footprint.width, height: footprint.height)
    }

    /// Whether `point` (view coordinates) is inside the *interactive/opaque*
    /// region. Below the menubar the whole footprint counts; within the top
    /// `menuBarHeight` strip only the central `neckWidth` (the notch) counts — so
    /// an expanded panel never captures or covers the menubar items flanking the
    /// notch. `clearMenuBar` is false while collapsed/ambient, where the whole
    /// footprint (including the ambient bar in the menubar strip) is interactive.
    public static func interactiveContains(_ point: CGPoint, footprint: CGSize,
                                           bounds: CGRect, flipped: Bool,
                                           neckWidth: CGFloat, menuBarHeight: CGFloat,
                                           clearMenuBar: Bool) -> Bool {
        let rect = hitRect(footprint: footprint, bounds: bounds, flipped: flipped)
        guard rect.contains(point) else { return false }
        guard clearMenuBar else { return true }
        let depthFromTop = flipped ? point.y - rect.minY : rect.maxY - point.y
        if depthFromTop >= menuBarHeight { return true }   // below the menubar → full width
        let halfNeck = min(neckWidth, footprint.width) / 2
        return abs(point.x - rect.midX) <= halfNeck
    }
}
