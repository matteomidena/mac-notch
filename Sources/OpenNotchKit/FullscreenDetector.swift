import CoreGraphics

/// One on-screen window reduced to what fullscreen detection needs.
/// `frame` and the display frame passed alongside must share a coordinate space
/// (CoreGraphics top-left origin, matching CGWindowListCopyWindowInfo bounds).
public struct WindowSnapshot: Equatable {
    public let frame: CGRect
    public let isOwnApp: Bool
    public init(frame: CGRect, isOwnApp: Bool) {
        self.frame = frame
        self.isOwnApp = isOwnApp
    }
}

/// Decides whether a *foreign* app is presenting fullscreen content over the notch.
///
/// There is no OS-level signal that covers every case: native macOS fullscreen
/// changes Space and hides the menubar, but Chromium in-window video fullscreen
/// (e.g. a YouTube video) does neither — it stays on the same Space with the
/// menubar present and merely fills the screen. The one reliable geometric tell
/// that separates both fullscreen kinds from an ordinary maximised window: the
/// content window reaches the display's *true* bottom edge (full frame height),
/// whereas a normal window respects the reserved visible frame and stops short.
public enum FullscreenDetector {
    /// True when another app owns a full-width window that starts at the top strip
    /// and extends to the display's bottom edge — i.e. fullscreen content.
    /// Our own windows are ignored so the overlay can never hide itself.
    ///
    /// - Parameters:
    ///   - bottomTolerance: slack (points) on the bottom-edge match. Must stay
    ///     below ~1pt: a maximised window sits exactly 1pt above the fullscreen
    ///     window, and that gap is the whole discriminator. On-device tunable.
    ///   - maxTopOffset: how far below the top a fullscreen content window may
    ///     start (native fullscreen starts at 0; Chromium starts below the
    ///     menubar, ~33pt). On-device tunable.
    public static func coversNotch(_ windows: [WindowSnapshot],
                                   mainDisplayFrame: CGRect,
                                   bottomTolerance: CGFloat = 0.5,
                                   maxTopOffset: CGFloat = 40) -> Bool {
        windows.contains { window in
            guard !window.isOwnApp else { return false }
            let f = window.frame
            let fullWidth = f.minX <= mainDisplayFrame.minX + 1
                         && f.width >= mainDisplayFrame.width - 1
            let startsAtTop = f.minY <= mainDisplayFrame.minY + maxTopOffset
            let reachesBottom = f.maxY >= mainDisplayFrame.maxY - bottomTolerance
            return fullWidth && startsAtTop && reachesBottom
        }
    }
}
