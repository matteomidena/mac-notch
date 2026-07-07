import CoreGraphics

/// AppKit global coordinates (bottom-left origin at the primary screen) ↔
/// CoreGraphics global coordinates (top-left origin at the primary screen,
/// the space CGWindowListCopyWindowInfo reports bounds in).
public enum CoordinateSpaces {
    public static func cgRect(fromAppKit rect: CGRect,
                              primaryScreenHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX,
               y: primaryScreenHeight - rect.maxY,
               width: rect.width, height: rect.height)
    }
}
