import AppKit
import SwiftUI
import OpenNotchKit

/// Borderless, non-activating panel pinned over the notch. Static: created once
/// at full size and never moved or resized — all animation is SwiftUI inside.
final class NotchWindow: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class NotchController: NSObject {
    private let notchWidth: CGFloat = 200
    private let fallbackPillSize = CGSize(width: 180, height: 32)
    private let expandedSize = CGSize(width: 500, height: 124)
    /// Fixed panel: expanded size + headroom for spring overshoot.
    private let panelSize = CGSize(width: 600, height: 184)
    private let hoverOutGrace: TimeInterval = 0.2

    private let screen: NSScreen
    private let panel: NotchWindow
    private let hostingView: PassthroughHostingView<NotchShell>
    private let model: NotchViewModel
    private let runtime: PluginRuntime
    // ponytail: the controller observes nowPlaying directly to size the ambient
    // bar. Fine for the single media plugin; generalize when a real compact-widget
    // API + multi-plugin composition lands.
    private let nowPlaying: NowPlayingService
    private var stateMachine = NotchStateMachine()
    private var trackingArea: NSTrackingArea?
    private var pendingHoverOut: DispatchWorkItem?
    private var coveredByFullscreen = false
    private var fullscreenPoll: Timer?
    private var localMonitor: Any?
    private var globalMonitor: Any?

    init(screen: NSScreen, runtime: PluginRuntime, nowPlaying: NowPlayingService) {
        self.screen = screen
        self.runtime = runtime
        self.nowPlaying = nowPlaying
        model = NotchViewModel(widgets: runtime.widgets)
        model.compactLeading = runtime.compactLeading.first
        model.compactTrailing = runtime.compactTrailing.first
        model.quickActions = runtime.quickActions
        model.notchGap = notchWidth

        hostingView = PassthroughHostingView(rootView: NotchShell(model: model))
        hostingView.autoresizingMask = [.width, .height]

        panel = NotchWindow(contentRect: CGRect(origin: .zero, size: panelSize),
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

        if screen.safeAreaInsets.top > 0 { model.topInset = screen.safeAreaInsets.top }
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            model.notchGap = max(80, screen.frame.width - left.width - right.width) + 6
        }
        model.showAmbient = (nowPlaying.current != nil)

        panel.setFrame(panelFrame(), display: false)
        hostingView.interactiveRect = { [weak self] in self?.hitRect() ?? .zero }
        hostingView.onDragChange = { [weak self] inside in
            self?.transition(inside ? .dragIn : .dragOut)
        }

        applyPhase(stateMachine.phase)
        installTrackingArea()
        installEventMonitors()
        observePlayback()
        observeFullscreen()
        observeQuickActions()
    }

    func show() { panel.orderFrontRegardless() }
    func hide() { panel.orderOut(nil) }

    // MARK: - Geometry (static)

    /// The one and only window frame: top-center over the notch, never changes.
    private func panelFrame() -> CGRect {
        CGRect(x: screen.frame.midX - panelSize.width / 2,
               y: screen.frame.maxY - panelSize.height,
               width: panelSize.width, height: panelSize.height)
    }

    private func notchSize() -> CGSize {
        let metrics = NotchGeometry.metrics(screenFrame: screen.frame,
                                            topInset: screen.safeAreaInsets.top,
                                            notchWidth: notchWidth,
                                            fallbackPillSize: fallbackPillSize)
        return metrics.anchorRect.size
    }

    private func ambientSize() -> CGSize {
        CGSize(width: model.notchGap + 94, height: model.topInset)
    }

    private func currentFootprint() -> CGSize {
        NotchFootprint.size(phase: stateMachine.phase, showAmbient: model.showAmbient,
                            notchSize: notchSize(), ambientSize: ambientSize(),
                            expandedSize: expandedSize)
    }

    private func hitRect() -> CGRect {
        NotchFootprint.hitRect(footprint: model.footprint,
                               bounds: hostingView.bounds,
                               flipped: hostingView.isFlipped)
    }

    // MARK: - Phase rendering

    private func applyPhase(_ phase: NotchPhase) {
        model.phase = phase
        model.footprint = currentFootprint()
        if phase == .hidden { panel.orderOut(nil) } else { panel.orderFrontRegardless() }
        installTrackingArea()   // tracking rect follows the footprint
    }

    private func transition(_ event: NotchEvent) {
        let before = stateMachine.phase
        let after = stateMachine.handle(event)
        guard after != before else { return }
        applyPhase(after)
    }

    // MARK: - Playback → ambient bar

    private func observePlayback() {
        withObservationTracking {
            _ = nowPlaying.current
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.playbackChanged()
                self?.observePlayback()
            }
        }
    }

    private func observeQuickActions() {
        withObservationTracking {
            _ = runtime.quickActions
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.model.quickActions = self?.runtime.quickActions ?? []
                self?.observeQuickActions()
            }
        }
    }

    private func playbackChanged() {
        model.showAmbient = (nowPlaying.current != nil)
        model.footprint = currentFootprint()   // SwiftUI animates the morph
        installTrackingArea()
    }

    // MARK: - Hover tracking

    private func installTrackingArea() {
        guard let contentView = panel.contentView else { return }
        if let trackingArea { contentView.removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: hitRect(),
                                  options: [.mouseEnteredAndExited, .activeAlways],
                                  owner: self,
                                  userInfo: nil)
        contentView.addTrackingArea(area)
        trackingArea = area
    }

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

    // MARK: - Click / escape monitors

    private func installEventMonitors() {
        // Local: clicks on our panel pin it; Escape (when we ever have key
        // status — e.g. Settings open) unpins. Global keyboard monitoring needs
        // Accessibility permission, so Escape is best-effort by design (spec M2.5).
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .keyDown]) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown {
                if event.keyCode == 53 { self.transition(.escape) }   // Escape
                return event
            }
            if event.window === self.panel {
                self.transition(.click)
            } else {
                self.transition(.clickOutside)
            }
            return event
        }
        // Global: clicks in OTHER apps unpin.
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.transition(.clickOutside) }
        }
    }

    // MARK: - Fullscreen tracking

    private var pollSuspended = false

    private func observeFullscreen() {
        let ws = NSWorkspace.shared.notificationCenter
        // Immediate triggers: space changes (native fullscreen) and frontmost-app
        // changes both warrant instant re-evaluation.
        ws.addObserver(self, selector: #selector(evaluateFullscreen),
                       name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        ws.addObserver(self, selector: #selector(evaluateFullscreen),
                       name: NSWorkspace.didActivateApplicationNotification, object: nil)
        // Poll gating: nothing changes while the display sleeps / session is locked.
        ws.addObserver(self, selector: #selector(suspendPoll),
                       name: NSWorkspace.screensDidSleepNotification, object: nil)
        ws.addObserver(self, selector: #selector(resumePoll),
                       name: NSWorkspace.screensDidWakeNotification, object: nil)
        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(self, selector: #selector(suspendPoll),
                        name: NSNotification.Name("com.apple.screenIsLocked"), object: nil)
        dnc.addObserver(self, selector: #selector(resumePoll),
                        name: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil)

        // Fallback poll: the ONLY mechanism that catches Chromium in-window video
        // fullscreen (no notification fires for it). 1s cadence, gated above.
        let poll = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.pollSuspended else { return }
                self.evaluateFullscreen()
            }
        }
        RunLoop.main.add(poll, forMode: .common)
        fullscreenPoll = poll
        evaluateFullscreen()
    }

    @objc private func suspendPoll() { pollSuspended = true }
    @objc private func resumePoll() {
        pollSuspended = false
        evaluateFullscreen()
    }

    @objc private func evaluateFullscreen() {
        let covered = FullscreenDetector.coversNotch(currentWindows(),
                                                     mainDisplayFrame: screenFrameCG())
        guard covered != coveredByFullscreen else { return }
        coveredByFullscreen = covered
        transition(covered ? .enterFullscreen : .exitFullscreen)
    }

    /// This screen's frame in CG (top-left-origin) coordinates, matching the
    /// window bounds returned by CGWindowListCopyWindowInfo.
    private func screenFrameCG() -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CoordinateSpaces.cgRect(fromAppKit: screen.frame,
                                       primaryScreenHeight: primaryHeight)
    }

    func tearDown() {
        fullscreenPoll?.invalidate()
        fullscreenPoll = nil
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        localMonitor = nil
        globalMonitor = nil
        pendingHoverOut?.cancel()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        DistributedNotificationCenter.default().removeObserver(self)
        panel.orderOut(nil)
    }

    private func currentWindows() -> [WindowSnapshot] {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let infos = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        return infos.compactMap { info in
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else {
                return nil
            }
            let pid = info[kCGWindowOwnerPID as String] as? pid_t
            return WindowSnapshot(frame: bounds, isOwnApp: pid == ownPID)
        }
    }
}
