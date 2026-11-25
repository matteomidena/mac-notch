import AppKit
import SwiftUI
import OpenNotchKit
import os

private let log = Logger(subsystem: "cafe.notch", category: "window")

/// Borderless, non-activating panel pinned over the notch. All animation is SwiftUI inside;
/// the window only switches between two top-anchored sizes (see `fitWindow`).
final class NotchWindow: NSPanel {
    /// Claude's menu-bar template icon from the installed desktop app, read-only; empty if absent.
    static func claudeMark() -> [AgentKind: Image] {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.anthropic.claudefordesktop"),
              let img = Bundle(url: url)?.image(forResource: "TrayIconTemplate") else { return [:] }
        img.isTemplate = true
        return [.claude: Image(nsImage: img)]
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class NotchController: NSObject {
    private let notchWidth: CGFloat = 200
    private let fallbackPillSize = CGSize(width: 180, height: 32)
    /// Fixed window: tallest panel (Agents cap) + 8 pt gap + 36 pt pill + spring headroom.
    private let panelSize = CGSize(width: 520, height: AgentsLayout.maxHeight + NotchViewModel.pillGap + NotchViewModel.pillHeight + 40)
    /// While collapsed the window hugs the bar: WindowServer composites the whole window on
    /// every animated frame (bars, pulse dot), so a short window costs far less.
    private var collapsedSize: CGSize { CGSize(width: panelSize.width, height: max(notchSize().height, model.topInset) + 12) }
    /// Shrinking waits for the close spring to settle, or it would clip the panel mid-flight.
    private let shrinkDelay: TimeInterval = 0.8
    private var pendingShrink: DispatchWorkItem?
    private static var loggedAmbient = false
    private let hoverOutGrace: TimeInterval = 0.2
    /// Dwell before opening on hover, so a cursor merely passing over the notch
    /// (e.g. on its way to a menubar item) doesn't fling the panel open.
    private let hoverInDwell: TimeInterval = 0.14

    private let screen: NSScreen
    private let panel: NotchWindow
    private let hostingView: PassthroughHostingView<NotchShell>
    private let model: NotchViewModel
    private let runtime: PluginRuntime
    // ponytail: the controller observes nowPlaying directly to size the ambient
    // bar. Fine for the single media plugin; generalize when a real compact-widget
    // API + multi-plugin composition lands.
    private let nowPlaying: NowPlayingService
    private let agents: AgentUsageService
    private var stateMachine = NotchStateMachine()
    private var cursorPoll: Timer?
    private var cursorInside = false
    private var pendingHoverOut: DispatchWorkItem?
    private var pendingHoverIn: DispatchWorkItem?
    private var coveredByFullscreen = false
    /// After a Space switch the notch stays out of the way: hover can't open it
    /// until this passes, and a cursor already under it must leave and come back.
    private var settleUntil = Date.distantPast
    private let spaceSettle: TimeInterval = 0.45
    private var fullscreenPoll: Timer?
    private var localMonitor: Any?
    private var moveMonitors: [Any] = []
    private var globalMonitor: Any?

    init(screen: NSScreen, runtime: PluginRuntime, nowPlaying: NowPlayingService, agents: AgentUsageService) {
        self.screen = screen
        self.runtime = runtime
        self.nowPlaying = nowPlaying
        self.agents = agents
        model = NotchViewModel(widgets: runtime.widgets)
        model.compactLeading = runtime.compactLeading.first
        model.compactTrailing = runtime.compactTrailing.first
        model.openLeading = runtime.openLeading.first
        model.openTrailing = runtime.openTrailing.first
        model.quickActions = runtime.quickActions
        model.notchGap = notchWidth
        model.tabs = runtime.tabs

        hostingView = PassthroughHostingView(rootView: NotchShell(model: model, agentMarks: NotchWindow.claudeMark()))
        hostingView.autoresizingMask = [.width, .height]

        panel = NotchWindow(contentRect: CGRect(origin: .zero, size: panelSize),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered,
                            defer: false)
        panel.level = .statusBar
        // Not .canJoinAllSpaces: a per-Space window slides out with its Space during a switch,
        // like the real menu bar, instead of staying put. spaceChanged() brings it to the new one.
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.contentView = hostingView
        // Start transparent to clicks; the cursor poll flips this to false only
        // while the cursor is over the interactive region. A nil hitTest does NOT
        // pass clicks through to the app below (the window server already picked
        // this frontmost non-ignoring window), so per-window mouse transparency is
        // the only thing that actually lets clicks reach what's behind the notch.
        panel.ignoresMouseEvents = true

        super.init()

        if screen.safeAreaInsets.top > 0 { model.topInset = screen.safeAreaInsets.top }
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            model.notchGap = max(80, screen.frame.width - left.width - right.width) + 6
        }
        model.showAmbient = ambientWanted()
        model.onSelectTab = { [weak self] in
            guard let self else { return }
            self.model.footprint = self.currentFootprint()
        }
        if !Self.loggedAmbient {
            Self.loggedAmbient = true
            log.info("ambient width \(Double(self.ambientSize().width))")
        }

        panel.setFrame(panelFrame(collapsedSize), display: false)
        hostingView.interactiveRect = { [weak self] in self?.hitRect() ?? .zero }
        hostingView.onDragChange = { [weak self] inside in
            self?.transition(inside ? .dragIn : .dragOut)
        }

        applyPhase(stateMachine.phase)
        startCursorTracking()
        installEventMonitors()
        observePlayback()
        observeFullscreen()
        observeQuickActions()
    }

    func show() { panel.orderFrontRegardless() }
    func hide() { panel.orderOut(nil) }

    // MARK: - Geometry (static)

    /// Top-center over the notch; the SwiftUI content is top-anchored, so only the bottom edge moves.
    private func panelFrame(_ size: CGSize) -> CGRect {
        CGRect(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height,
               width: size.width, height: size.height)
    }

    /// Full size at once when the notch opens; the collapsed size once the close has settled.
    private func fitWindow(for phase: NotchPhase) {
        pendingShrink?.cancel(); pendingShrink = nil
        if phase == .expanded || phase == .pinned || phase == .alert {
            if panel.frame.height != panelSize.height { panel.setFrame(panelFrame(panelSize), display: true) }
            return
        }
        let shrink = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.panel.setFrame(self.panelFrame(self.collapsedSize), display: true)
            self.updateCursorTracking()
        }
        pendingShrink = shrink
        DispatchQueue.main.asyncAfter(deadline: .now() + shrinkDelay, execute: shrink)
    }

    private func notchSize() -> CGSize {
        let metrics = NotchGeometry.metrics(screenFrame: screen.frame,
                                            topInset: screen.safeAreaInsets.top,
                                            notchWidth: notchWidth,
                                            fallbackPillSize: fallbackPillSize)
        return metrics.anchorRect.size
    }

    private func ambientSize() -> CGSize {
        CGSize(width: model.notchGap + NotchViewModel.wing
                      + (model.leadingWing ? NotchViewModel.wing : NotchViewModel.bareWing),
               height: model.topInset)
    }

    /// Ambient bar shows while media plays or any plan limit exists. A paused or
    /// ended session (macOS drops its menu bar icon) doesn't count.
    private func ambientWanted() -> Bool {
        model.leadingWing = nowPlaying.current?.isPlaying ?? false
        return model.leadingWing || !agents.limits.isEmpty || agents.liveSessions.contains(where: \.needsYou)
    }

    private var expandedSize: CGSize {
        CGSize(width: NotchViewModel.panelWidth,
               height: NotchViewModel.panelHeight(forTab: model.selectedTab,
                                                  limitRows: agents.limits.reduce(0) { $0 + $1.windows.count },
                                                  sessionRows: agents.liveSessions.count))
    }

    private func currentFootprint() -> CGSize {
        NotchFootprint.size(phase: stateMachine.phase, showAmbient: model.showAmbient,
                            notchSize: notchSize(), ambientSize: ambientSize(),
                            expandedSize: expandedSize,
                            alertSize: notchSize())  // placeholder: the strip size is wired with the runaway strip
    }

    /// The mouse-interactive region. When open, the whole expanded panel (so its
    /// buttons work). When collapsed, ONLY the physical notch — never the wider
    /// ambient bar or the empty space the panel *would* occupy — so hovering the
    /// notch opens it, but clicks anywhere else fall through to what's behind.
    private func hoverFootprint() -> CGSize {
        switch stateMachine.phase {
        case .expanded, .pinned:   // panel + gap + pill
            return CGSize(width: model.footprint.width,
                          height: model.footprint.height + NotchViewModel.pillGap + NotchViewModel.pillHeight)
        default: return notchSize()
        }
    }

    private func hitRect() -> CGRect {
        NotchFootprint.hitRect(footprint: hoverFootprint(),
                               bounds: hostingView.bounds,
                               flipped: hostingView.isFlipped)
    }

    // MARK: - Phase rendering

    private func applyPhase(_ phase: NotchPhase) {
        fitWindow(for: phase)
        model.phase = phase
        model.footprint = currentFootprint()
        if phase == .hidden { panel.orderOut(nil) } else { panel.orderFrontRegardless() }
    }

    private func transition(_ event: NotchEvent) {
        let before = stateMachine.phase
        let after = stateMachine.handle(event)
        guard after != before else { return }
        let isOpen = after == .expanded || after == .pinned
        if isOpen && !(before == .expanded || before == .pinned) {
            // Each open starts on the default tab; a click then sticks until close.
            model.tabs = runtime.tabs
            model.widgets = runtime.widgets
            model.quickActions = runtime.quickActions
            model.selectedTab = TabBar.defaultTab(model.tabItems,
                                                  hasLiveSession: !agents.liveSessions.isEmpty,
                                                  isPlaying: nowPlaying.current?.isPlaying ?? false)
        }
        applyPhase(after)
        if after == .expanded || after == .pinned { agents.refreshLimits() }  // re-filters stale live sessions
    }

    // MARK: - Playback → ambient bar

    private func observePlayback() {
        withObservationTracking {
            _ = nowPlaying.current
            _ = agents.limits
            _ = agents.liveSessions   // the Agents panel height follows both
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
        model.showAmbient = ambientWanted()
        model.footprint = currentFootprint()   // SwiftUI animates the morph
    }

    // MARK: - Cursor tracking (hover + click-through)

    /// The interactive region in screen (bottom-left origin) coordinates — the
    /// notch when collapsed, the whole panel when open.
    private func interactiveScreenRect() -> CGRect {
        let r = hitRect()   // hostingView coords: flipped, y measured from the top
        let f = panel.frame
        return CGRect(x: f.minX + r.minX, y: f.maxY - r.maxY,
                      width: r.width, height: r.height)
    }

    /// Track the cursor from mouse-move events: a tracking area can't work because the
    /// window ignores mouse events over passthrough regions (so it would never get
    /// mouseEntered). Mouse-move monitors need no permission and cost nothing while the
    /// mouse is still. A slow poll catches the shape changing under a still cursor.
    private func startCursorTracking() {
        let moves: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        moveMonitors = [
            NSEvent.addGlobalMonitorForEvents(matching: moves) { [weak self] _ in
                MainActor.assumeIsolated { self?.updateCursorTracking() }
            },
            NSEvent.addLocalMonitorForEvents(matching: moves) { [weak self] event in
                self?.updateCursorTracking(); return event
            },
        ].compactMap { $0 }
        // ponytail: 5 Hz fallback; raise it if hover ever feels late after the panel resizes.
        let poll = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.pollSuspended else { return }
                self.updateCursorTracking()
            }
        }
        RunLoop.main.add(poll, forMode: .common)
        cursorPoll = poll
    }

    private func updateCursorTracking() {
        let inside = interactiveScreenRect().contains(NSEvent.mouseLocation)
        guard inside != cursorInside else { return }
        panel.ignoresMouseEvents = !inside  // a WindowServer call: only when it changes
        cursorInside = inside
        if Date() < settleUntil { return }  // settling after a Space switch: track, don't open
        if inside { cursorEntered() } else { cursorExited() }
    }

    private func cursorEntered() {
        pendingHoverOut?.cancel()
        pendingHoverOut = nil
        // Open only if the cursor lingers over the notch — a quick pass-through
        // toward the menubar shouldn't trigger it.
        let workItem = DispatchWorkItem { [weak self] in self?.transition(.hoverIn) }
        pendingHoverIn?.cancel()
        pendingHoverIn = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + hoverInDwell, execute: workItem)
    }

    private func cursorExited() {
        pendingHoverIn?.cancel()
        pendingHoverIn = nil
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
            // Only a click that actually lands on the visible notch/panel counts.
            // event.window == panel is true for the whole oversized frame, incl.
            // the transparent regions that hitTest passes through — so also check
            // the click sits inside the interactive rect, else it's "outside".
            let onNotch = event.window === self.panel
                && self.hitRect().contains(self.hostingView.convert(event.locationInWindow, from: nil))
            self.transition(onNotch ? .click : .clickOutside)
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
        ws.addObserver(self, selector: #selector(spaceChanged),
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

    /// Space switch (swipe, full-screen app): the panel left with the old Space; move it here hidden,
    /// then fade it in once the switch has settled,
    /// instead of popping open under a cursor that happens to be at the top.
    @objc private func spaceChanged() {
        pendingHoverIn?.cancel(); pendingHoverIn = nil
        if stateMachine.phase == .expanded { transition(.hoverOut) }
        settleUntil = Date().addingTimeInterval(spaceSettle)
        panel.alphaValue = 0
        panel.orderFrontRegardless()  // .moveToActiveSpace: follow the user into the new Space
        evaluateFullscreen()
        DispatchQueue.main.asyncAfter(deadline: .now() + spaceSettle) { [weak self] in
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.3
                self?.panel.animator().alphaValue = 1
            }
        }
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
        cursorPoll?.invalidate()
        cursorPoll = nil
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        moveMonitors.forEach(NSEvent.removeMonitor)
        moveMonitors = []
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        localMonitor = nil
        globalMonitor = nil
        pendingHoverOut?.cancel()
        pendingHoverIn?.cancel()
        pendingShrink?.cancel()
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
