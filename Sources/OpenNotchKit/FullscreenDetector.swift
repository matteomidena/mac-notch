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
/// The reliable geometric tell that separates fullscreen from an ordinary
/// maximised window is that fullscreen content **covers the menubar strip** —
/// its top reaches the display's true top edge (minY ≈ 0). A maximised window
/// leaves the menubar visible and starts *below* it (minY = menubar height), so
/// its top never reaches 0.
///
/// The earlier heuristic instead keyed off the *bottom* edge (fullscreen reaches
/// the true bottom, a maximised window stops ~1pt short because the Dock reserves
/// that space). That breaks when the Dock is auto-hidden: a maximised window then
/// fills the whole visible frame down to the true bottom edge and is
/// indistinguishable from fullscreen by the bottom edge alone.
///
/// Trade-off: in-window video fullscreen that keeps the system menubar visible
/// (some Chromium video modes) starts below the menubar and is therefore no
/// longer detected geometrically. Native macOS fullscreen (which hides the
/// menubar and covers from the top, and also fires activeSpaceDidChange) still
/// is. `topTolerance` is the on-device tuning knob for this.
public enum FullscreenDetector {
    /// True when another app owns a full-width window that covers the menubar
    /// strip and extends to the display's bottom edge — i.e. fullscreen content.
    /// Our own windows are ignored so the overlay can never hide itself.
    ///
    /// - Parameters:
    ///   - bottomTolerance: slack (points) on the bottom-edge match. On-device tunable.
    ///   - topTolerance: how far below the display top a fullscreen window may
    ///     start and still count as covering the menubar. Keep small (< menubar
    ///     height) so a maximised window starting at the menubar bottom is
    ///     excluded. On-device tunable.
    public static func coversNotch(_ windows: [WindowSnapshot],
                                   mainDisplayFrame: CGRect,
                                   bottomTolerance: CGFloat = 0.5,
                                   topTolerance: CGFloat = 2) -> Bool {
        windows.contains { window in
            guard !window.isOwnApp else { return false }
            let f = window.frame
            let fullWidth = f.minX <= mainDisplayFrame.minX + 1
                         && f.width >= mainDisplayFrame.width - 1
            let coversMenuBar = f.minY <= mainDisplayFrame.minY + topTolerance
            let reachesBottom = f.maxY >= mainDisplayFrame.maxY - bottomTolerance
            return fullWidth && coversMenuBar && reachesBottom
        }
    }
}
