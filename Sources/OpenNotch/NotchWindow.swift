import AppKit
import SwiftUI
import OpenNotchKit

/// Borderless, non-activating panel that sits over the physical notch and
/// expands/collapses in response to hover and fullscreen state.
final class NotchWindow: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class NotchController: NSObject {
    private let notchWidth: CGFloat = 200
    private let fallbackPillSize = CGSize(width: 180, height: 32)
    private let expandedSize = CGSize(width: 420, height: 160)
    private let hoverOutGrace: TimeInterval = 0.2

    private let panel: NotchWindow
    private let hostingView: NSHostingView<NotchShell>
    private let model: NotchViewModel
    private var stateMachine = NotchStateMachine()
    private var trackingArea: NSTrackingArea?
    private var pendingHoverOut: DispatchWorkItem?
    private var pendingShrink: DispatchWorkItem?

    init(widgets: [PluginWidget] = []) {
        model = NotchViewModel(widgets: widgets)

        let initialFrame = CGRect(origin: .zero, size: fallbackPillSize)
        hostingView = NSHostingView(rootView: NotchShell(model: model))
        hostingView.frame = initialFrame
        hostingView.autoresizingMask = [.width, .height]  // track the window during resize

        panel = NotchWindow(contentRect: initialFrame,
                             styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered,
                             defer: false)
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.contentView = hostingView
        panel.ignoresMouseEvents = false

        super.init()

        panel.setFrame(anchorRect(), display: false)
        installTrackingArea()
        observeFullscreenNotifications()
    }

    func show() {
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }

    func updateWidgets(_ widgets: [PluginWidget]) {
        model.widgets = widgets
    }

    // MARK: - Geometry

    private func anchorRect() -> CGRect {
        guard let screen = NSScreen.main else {
            return CGRect(origin: .zero, size: fallbackPillSize)
        }
        let metrics = NotchGeometry.metrics(screenFrame: screen.frame,
                                             topInset: screen.safeAreaInsets.top,
                                             notchWidth: notchWidth,
                                             fallbackPillSize: fallbackPillSize)
        return metrics.anchorRect
    }

    private func expandedRect() -> CGRect {
        let anchor = anchorRect()
        let origin = CGPoint(x: anchor.midX - expandedSize.width / 2,
                              y: anchor.maxY - expandedSize.height)
        return CGRect(origin: origin, size: expandedSize)
    }

    private func applyFrame(for phase: NotchPhase, animated: Bool) {
        pendingShrink?.cancel(); pendingShrink = nil
        switch phase {
        case .hidden:
            model.phase = .hidden
            panel.orderOut(nil)
        case .expanded:
            // Grow the window to the full canvas BEFORE the spring so the
            // expanding panel is never clipped, then animate it open.
            panel.setFrame(expandedRect(), display: true)
            panel.orderFrontRegardless()
            model.phase = .expanded
        case .collapsed:
            panel.orderFrontRegardless()
            model.phase = .collapsed
            // Keep the full canvas during the close animation, then shrink the
            // window to the notch footprint so it doesn't block the menu bar.
            let anchor = anchorRect()
            if animated {
                let work = DispatchWorkItem { [weak self] in
                    guard let self, self.stateMachine.phase == .collapsed else { return }
                    self.panel.setFrame(anchor, display: true)
                }
                pendingShrink = work
                // Longer than the bouncy settle time so the close isn't clipped.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.65, execute: work)
            } else {
                panel.setFrame(anchor, display: true)
            }
        }
    }

    // MARK: - Hover tracking

    private func installTrackingArea() {
        guard let contentView = panel.contentView else { return }
        if let trackingArea {
            contentView.removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(rect: contentView.bounds,
                                   options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                   owner: self,
                                   userInfo: nil)
        contentView.addTrackingArea(area)
        trackingArea = area
    }

    // Explicit ObjC selectors: NSTrackingArea sends `mouseEntered:`/`mouseExited:`
    // to its owner. Swift would otherwise mangle these to `mouseEnteredWith:`.
    @objc(mouseEntered:) func mouseEntered(with event: NSEvent) {
        pendingHoverOut?.cancel()
        pendingHoverOut = nil
        transition(.hoverIn)
    }

    @objc(mouseExited:) func mouseExited(with event: NSEvent) {
        let workItem = DispatchWorkItem { [weak self] in
            self?.transition(.hoverOut)
        }
        pendingHoverOut?.cancel()
        pendingHoverOut = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + hoverOutGrace, execute: workItem)
    }

    // MARK: - Fullscreen tracking

    private func observeFullscreenNotifications() {
        // ponytail: NSWorkspace.activeSpaceDidChangeNotification fires on any Space
        // switch, not just fullscreen apps. NSWindow.didEnter/ExitFullScreen are the
        // precise per-app signals; that's what we key phase transitions off of.
        NotificationCenter.default.addObserver(self,
                                                selector: #selector(handleEnterFullscreen),
                                                name: NSWindow.didEnterFullScreenNotification,
                                                object: nil)
        NotificationCenter.default.addObserver(self,
                                                selector: #selector(handleExitFullscreen),
                                                name: NSWindow.didExitFullScreenNotification,
                                                object: nil)
    }

    @objc private func handleEnterFullscreen() {
        transition(.enterFullscreen)
    }

    @objc private func handleExitFullscreen() {
        transition(.exitFullscreen)
    }

    // MARK: - State machine

    private func transition(_ event: NotchEvent) {
        let newPhase = stateMachine.handle(event)
        applyFrame(for: newPhase, animated: true)
    }
}
