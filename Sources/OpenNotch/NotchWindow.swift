import AppKit
import SwiftUI
import OpenNotchKit

/// Borderless, non-activating panel that sits over the physical notch and
/// expands/collapses in response to hover and fullscreen state.
final class NotchWindow: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// When set, `animator().setFrame` uses this spring for the frame animation
    /// (GPU-driven, real overshoot) instead of the context's timing function.
    var frameSpring: CASpringAnimation?
    override func animation(forKey key: NSAnimatablePropertyKey) -> Any? {
        if key == "frame", let frameSpring { return frameSpring }
        return super.animation(forKey: key)
    }
}

/// Build a `CASpringAnimation` for the window frame from SwiftUI-style params.
/// `response` = perceptual duration, `damping` = fraction (1 = no overshoot).
private func frameSpring(response: Double, damping: Double) -> CASpringAnimation {
    let s = CASpringAnimation(keyPath: "frame")
    s.mass = 1
    s.stiffness = pow(2 * .pi / response, 2) * s.mass
    s.damping = 4 * .pi * damping * s.mass / response
    s.initialVelocity = 0
    s.duration = s.settlingDuration
    return s
}

@MainActor
final class NotchController: NSObject {
    private let notchWidth: CGFloat = 200
    private let fallbackPillSize = CGSize(width: 180, height: 32)
    private let expandedSize = CGSize(width: 500, height: 124)
    private let hoverOutGrace: TimeInterval = 0.2

    private let panel: NotchWindow
    private let hostingView: NSHostingView<NotchShell>
    private let model: NotchViewModel
    private let runtime: PluginRuntime
    // ponytail: the controller observes nowPlaying directly to size the ambient
    // bar. Fine for the single media plugin; generalize when a real compact-widget
    // API + multi-plugin composition lands.
    private let nowPlaying: NowPlayingService
    private var stateMachine = NotchStateMachine()
    private var trackingArea: NSTrackingArea?
    private var pendingHoverOut: DispatchWorkItem?
    private var hoverUnlock: DispatchWorkItem?
    // While the open spring settles, its overshoot oscillation wobbles the window
    // edges across a stationary cursor — which would fire enter/exit repeatedly
    // and loop open/close. Ignore hover events until it settles, then re-check.
    private var hoverLocked = false
    private var coveredByFullscreen = false
    private var fullscreenPoll: Timer?

    init(runtime: PluginRuntime, nowPlaying: NowPlayingService) {
        self.runtime = runtime
        self.nowPlaying = nowPlaying
        model = NotchViewModel(widgets: runtime.widgets)
        // NOTE: if a live plugin-reload path is added later, it must re-push
        // compactLeading/compactTrailing (not just widgets) into the model.
        model.compactLeading = runtime.compactLeading.first
        model.compactTrailing = runtime.compactTrailing.first
        model.quickActions = runtime.quickActions
        model.notchGap = notchWidth

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

        // Reserve the real notch height (menubar height when there's no notch) so
        // the expanded content hangs below the notch, not over it.
        if let inset = NSScreen.main?.safeAreaInsets.top, inset > 0 { model.topInset = inset }

        // Measure the ACTUAL notch width from the areas flanking it, so the
        // ambient bar's transparent middle gap matches the hardware exactly.
        if let screen = NSScreen.main,
           let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            model.notchGap = max(80, screen.frame.width - left.width - right.width) + 6
        }

        model.showAmbient = (nowPlaying.current != nil)
        panel.setFrame(collapsedFrame(), display: false)
        installTrackingArea()
        observePlayback()
        observeFullscreen()
        observeQuickActions()
    }

    func show() {
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
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

    /// Collapsed footprint: a wide ambient bar wrapping the notch when there's
    /// media to show, otherwise the bare notch shape.
    private func collapsedFrame() -> CGRect {
        let anchor = anchorRect()
        guard model.showAmbient else { return anchor }
        let height = model.topInset                 // stay within the notch/menubar strip
        let width = model.notchGap + 94             // notch gap + flanking content + side padding
        let origin = CGPoint(x: anchor.midX - width / 2, y: anchor.maxY - height)
        return CGRect(origin: origin, size: CGSize(width: width, height: height))
    }

    // MARK: - Playback → ambient bar

    private func observePlayback() {
        withObservationTracking {
            _ = nowPlaying.current            // track changes to now-playing state
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.playbackChanged()
                self?.observePlayback()       // re-arm (withObservationTracking is one-shot)
            }
        }
    }

    private func observeQuickActions() {
        withObservationTracking {
            _ = runtime.quickActions            // establishes dependency on store.bundleIds
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.model.quickActions = self?.runtime.quickActions ?? []
                self?.observeQuickActions()     // re-arm (one-shot)
            }
        }
    }

    private func playbackChanged() {
        model.showAmbient = (nowPlaying.current != nil)
        // Resize the collapsed footprint live if we're currently collapsed.
        if stateMachine.phase == .collapsed {
            panel.setFrame(collapsedFrame(), display: true, animate: true)
        }
    }

    private func applyFrame(for phase: NotchPhase, animated: Bool) {
        switch phase {
        case .hidden:
            model.phase = .hidden
            panel.orderOut(nil)
        case .expanded, .pinned:
            panel.orderFrontRegardless()
            model.phase = phase
            // Animate the window growing downward from the notch (top edge stays
            // anchored). The black panel fills the window, so the menubar strip is
            // solid from the first frame — no transparent flash. Mirrors the close.
            let target = expandedRect()
            if animated {
                // Dynamic-Island drop: a real spring with overshoot. The top edge
                // stays pinned (origin.y and height move on one shared fraction).
                let spring = frameSpring(response: 0.4, damping: 0.62)
                panel.frameSpring = spring
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = spring.settlingDuration
                    panel.animator().setFrame(target, display: true)
                }
                lockHover(for: min(spring.settlingDuration, 0.55))
            } else {
                panel.frameSpring = nil
                panel.setFrame(target, display: true)
            }
        case .collapsed:
            panel.orderFrontRegardless()
            model.phase = .collapsed
            // Retract the window to the collapsed footprint (ambient bar or bare
            // notch). The panel fills the window, so animating the frame down IS
            // the close animation — the black panel shrinks smoothly into the notch.
            let target = collapsedFrame()
            panel.frameSpring = nil   // keep the smooth easeOut close
            if animated {
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.26
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    panel.animator().setFrame(target, display: true)
                }
            } else {
                panel.setFrame(target, display: true)
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
        guard !hoverLocked else { return }
        pendingHoverOut?.cancel()
        pendingHoverOut = nil
        transition(.hoverIn)
    }

    @objc(mouseExited:) func mouseExited(with event: NSEvent) {
        guard !hoverLocked else { return }
        let workItem = DispatchWorkItem { [weak self] in
            self?.transition(.hoverOut)
        }
        pendingHoverOut?.cancel()
        pendingHoverOut = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + hoverOutGrace, execute: workItem)
    }

    /// Ignore hover events for `duration` (the open spring's settle), then collapse
    /// if the cursor genuinely left during it — so the overshoot wobble can't loop.
    private func lockHover(for duration: TimeInterval) {
        hoverLocked = true
        hoverUnlock?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.hoverLocked = false
            if !NSMouseInRect(NSEvent.mouseLocation, self.panel.frame, false) {
                self.transition(.hoverOut)
            }
        }
        hoverUnlock = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    // MARK: - Fullscreen tracking

    private func observeFullscreen() {
        // NSWindow.didEnter/ExitFullScreenNotification only fire for our OWN
        // windows, which never go fullscreen — useless here. Native fullscreen
        // fires activeSpaceDidChange, but Chromium in-window video fullscreen
        // (a YouTube video) changes nothing observable — so poll the window list.
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(evaluateFullscreen),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil)
        // ponytail: 1s poll of the window list — the only mechanism that catches
        // in-window video fullscreen (no notification fires). Cheap; raise the
        // cadence if hide-on-fullscreen feels laggy.
        let poll = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.evaluateFullscreen() }
        }
        RunLoop.main.add(poll, forMode: .common)
        fullscreenPoll = poll
        evaluateFullscreen()   // initial state (e.g. launched into a fullscreen space)
    }

    /// Snapshot the on-screen windows and edge-trigger hide/show.
    @objc private func evaluateFullscreen() {
        let covered = FullscreenDetector.coversNotch(currentWindows(),
                                                     mainDisplayFrame: mainDisplayFrameCG())
        guard covered != coveredByFullscreen else { return }
        coveredByFullscreen = covered
        transition(covered ? .enterFullscreen : .exitFullscreen)
    }

    /// Main display frame in CoreGraphics (top-left origin) coordinates, matching
    /// the window bounds returned by CGWindowListCopyWindowInfo.
    private func mainDisplayFrameCG() -> CGRect {
        guard let size = NSScreen.main?.frame.size else { return .zero }
        return CGRect(origin: .zero, size: size)
    }

    private func currentWindows() -> [WindowSnapshot] {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let infos = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        return infos.compactMap { info in
            // Only normal-layer windows (layer 0); skip menubar/dock/status items.
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else {
                return nil
            }
            let pid = info[kCGWindowOwnerPID as String] as? pid_t
            return WindowSnapshot(frame: bounds, isOwnApp: pid == ownPID)
        }
    }

    // MARK: - State machine

    private func transition(_ event: NotchEvent) {
        let newPhase = stateMachine.handle(event)
        applyFrame(for: newPhase, animated: true)
    }
}
