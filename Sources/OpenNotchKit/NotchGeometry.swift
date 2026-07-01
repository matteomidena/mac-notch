import CoreGraphics

public struct NotchMetrics: Equatable {
    public let anchorRect: CGRect
    public let hasNotch: Bool
}

public enum NotchGeometry {
    public static func metrics(screenFrame: CGRect, topInset: CGFloat,
                               notchWidth: CGFloat,
                               fallbackPillSize: CGSize) -> NotchMetrics {
        let hasNotch = topInset > 0
        let size = hasNotch ? CGSize(width: notchWidth, height: topInset) : fallbackPillSize
        let origin = CGPoint(x: screenFrame.midX - size.width / 2,
                             y: screenFrame.maxY - size.height)
        return NotchMetrics(anchorRect: CGRect(origin: origin, size: size), hasNotch: hasNotch)
    }
}
