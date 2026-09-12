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
}
