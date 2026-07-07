# OpenNotch v2 — Milestone M2 (Foundation Hardening) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild the animation substrate on a static window, make OpenNotch a real double-clickable `.app`, add multi-display support, event-driven fullscreen detection, media robustness (supervision, scrubber, source badge), and pin/drag interactions.

**Architecture:** The spec is `docs/superpowers/specs/2026-07-07-open-notch-v2-design.md` — read it first. This plan covers **M2 only**. After M2 is merged and its manual DoD walked, write the M3 plan from the spec using the writing-plans skill (same for M4, M5). Pure logic goes in `OpenNotchKit` test-first; AppKit/window code goes in `OpenNotch` and is verified by the manual DoD checklist at the end.

**Tech Stack:** Swift 6 SPM package, SwiftUI + AppKit, swift-testing (`@Test`/`#expect`), vendored mediaremote-adapter (perl).

## Global Constraints

- Platform floor: macOS 14 (`platforms: [.macOS(.v14)]` in Package.swift). Swift tools 6.0.
- **No new dependencies.** The only package dependency is swift-testing, tests only.
- Tests use `import Testing` (`@Test`, `#expect`) — never XCTest.
- **Pure/executable split:** domain logic in `Sources/OpenNotchKit` (unit-tested, test-first); window/AppKit code in `Sources/OpenNotch` (manual DoD).
- **Plugins import only SwiftUI.** `Sources/OpenNotchKit` files that are plugin-visible must not import AppKit. (`NSImage(data:)` via `import SwiftUI` is allowed — see `ArtworkView`.)
- Run tests with `swift test`. Build with `swift build`. Run the app with `swift run OpenNotch` from the package root.
- Commit style: `feat(kit):` for OpenNotchKit, `feat:`/`fix:` for the executable, `docs:`, `test:`. Commit after every task at minimum; every green test cycle ideally.
- Animation feel constants (from spec): open spring `response: 0.4, dampingFraction: 0.7`; close spring `response: 0.3, dampingFraction: 0.85`. Keep them as named constants in one place — they are on-device tuning knobs.

---

### Task 1: Extend the notch state machine (pin, click, escape, drag)

**Files:**
- Modify: `Sources/OpenNotchKit/NotchState.swift`
- Test: `Tests/OpenNotchKitTests/NotchStateTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `NotchPhase` gains case `pinned`. `NotchEvent` gains cases `click`, `clickOutside`, `escape`, `dragIn`, `dragOut`. `NotchStateMachine.handle(_:) -> NotchPhase` unchanged signature. Semantics: `click` pins (from collapsed or expanded); a pinned notch ignores `hoverOut` and further `click`s (buttons inside the panel send clicks too — click must never close); only `clickOutside`, `escape`, or fullscreen close a pinned notch.

- [ ] **Step 1: Write the failing tests**

Append to `Tests/OpenNotchKitTests/NotchStateTests.swift`:

```swift
@Test func clickPinsFromCollapsedAndExpanded() {
    var sm = NotchStateMachine(phase: .collapsed)
    #expect(sm.handle(.click) == .pinned)
    sm = NotchStateMachine(phase: .expanded)
    #expect(sm.handle(.click) == .pinned)
}

@Test func pinnedIgnoresHoverOutAndClick() {
    var sm = NotchStateMachine(phase: .pinned)
    #expect(sm.handle(.hoverOut) == .pinned)
    #expect(sm.handle(.click) == .pinned)
    #expect(sm.handle(.hoverIn) == .pinned)
}

@Test func clickOutsideAndEscapeCollapse() {
    var sm = NotchStateMachine(phase: .pinned)
    #expect(sm.handle(.clickOutside) == .collapsed)
    sm = NotchStateMachine(phase: .pinned)
    #expect(sm.handle(.escape) == .collapsed)
    sm = NotchStateMachine(phase: .expanded)
    #expect(sm.handle(.escape) == .collapsed)
}

@Test func clickIgnoredWhenHidden() {
    var sm = NotchStateMachine(phase: .hidden)
    #expect(sm.handle(.click) == .hidden)
}

@Test func dragInExpandsDragOutCollapses() {
    var sm = NotchStateMachine(phase: .collapsed)
    #expect(sm.handle(.dragIn) == .expanded)
    #expect(sm.handle(.dragOut) == .collapsed)
}

@Test func dragIgnoredWhenHiddenOrPinned() {
    var sm = NotchStateMachine(phase: .hidden)
    #expect(sm.handle(.dragIn) == .hidden)
    sm = NotchStateMachine(phase: .pinned)
    #expect(sm.handle(.dragOut) == .pinned)
}

@Test func fullscreenHidesPinned() {
    var sm = NotchStateMachine(phase: .pinned)
    #expect(sm.handle(.enterFullscreen) == .hidden)
    #expect(sm.handle(.exitFullscreen) == .collapsed)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter NotchStateTests`
Expected: FAIL — `pinned`, `click`, etc. don't exist (compile errors count as the failing state here).

- [ ] **Step 3: Implement**

Replace the body of `Sources/OpenNotchKit/NotchState.swift`:

```swift
public enum NotchPhase: Equatable { case collapsed, expanded, pinned, hidden }
public enum NotchEvent: Equatable {
    case hoverIn, hoverOut
    case click, clickOutside, escape
    case dragIn, dragOut
    case enterFullscreen, exitFullscreen
}

public struct NotchStateMachine {
    public private(set) var phase: NotchPhase
    public init(phase: NotchPhase = .collapsed) { self.phase = phase }

    public mutating func handle(_ event: NotchEvent) -> NotchPhase {
        switch event {
        case .enterFullscreen: phase = .hidden
        case .exitFullscreen:  phase = .collapsed
        case .hoverIn:  if phase == .collapsed { phase = .expanded }
        case .hoverOut: if phase == .expanded { phase = .collapsed }
        case .click:
            // Pins open. Never closes: clicks on buttons inside the panel also
            // arrive here, and interacting must not dismiss the panel.
            if phase == .collapsed || phase == .expanded { phase = .pinned }
        case .clickOutside, .escape:
            if phase == .expanded || phase == .pinned { phase = .collapsed }
        case .dragIn:  if phase == .collapsed { phase = .expanded }
        case .dragOut: if phase == .expanded { phase = .collapsed }
        }
        return phase
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter NotchStateTests`
Expected: PASS (old tests still green — `hoverIn` from `expanded` stays `expanded`).

- [ ] **Step 5: Commit**

```bash
git add Sources/OpenNotchKit/NotchState.swift Tests/OpenNotchKitTests/NotchStateTests.swift
git commit -m "feat(kit): notch FSM gains pinned phase + click/escape/drag events"
```

---

### Task 2: Footprint & hit-region geometry (pure)

**Files:**
- Create: `Sources/OpenNotchKit/NotchFootprint.swift`
- Test: `Tests/OpenNotchKitTests/NotchFootprintTests.swift`

**Interfaces:**
- Consumes: `NotchPhase` (Task 1).
- Produces:
  - `NotchFootprint.size(phase: NotchPhase, showAmbient: Bool, notchSize: CGSize, ambientSize: CGSize, expandedSize: CGSize) -> CGSize` — the visible shape's size inside the fixed panel. `hidden` returns `notchSize` (the window is ordered out anyway; avoids a from-zero morph on re-show).
  - `NotchFootprint.hitRect(footprint: CGSize, bounds: CGRect, flipped: Bool) -> CGRect` — the top-center rect the shape occupies in view coordinates; used for hit-testing and the tracking area.

- [ ] **Step 1: Write the failing tests**

Create `Tests/OpenNotchKitTests/NotchFootprintTests.swift`:

```swift
import Testing
import CoreGraphics
@testable import OpenNotchKit

private let notch = CGSize(width: 200, height: 32)
private let ambient = CGSize(width: 300, height: 32)
private let expanded = CGSize(width: 500, height: 124)

@Test func collapsedIsNotchOrAmbient() {
    #expect(NotchFootprint.size(phase: .collapsed, showAmbient: false,
                                notchSize: notch, ambientSize: ambient, expandedSize: expanded) == notch)
    #expect(NotchFootprint.size(phase: .collapsed, showAmbient: true,
                                notchSize: notch, ambientSize: ambient, expandedSize: expanded) == ambient)
}

@Test func expandedAndPinnedUseExpandedSize() {
    for phase in [NotchPhase.expanded, .pinned] {
        #expect(NotchFootprint.size(phase: phase, showAmbient: true,
                                    notchSize: notch, ambientSize: ambient, expandedSize: expanded) == expanded)
    }
}

@Test func hiddenKeepsNotchSize() {
    #expect(NotchFootprint.size(phase: .hidden, showAmbient: true,
                                notchSize: notch, ambientSize: ambient, expandedSize: expanded) == notch)
}

@Test func hitRectIsTopCentered() {
    let bounds = CGRect(x: 0, y: 0, width: 600, height: 184)
    let fp = CGSize(width: 500, height: 124)
    // Non-flipped (AppKit default): top = maxY.
    #expect(NotchFootprint.hitRect(footprint: fp, bounds: bounds, flipped: false)
            == CGRect(x: 50, y: 60, width: 500, height: 124))
    // Flipped: top = minY.
    #expect(NotchFootprint.hitRect(footprint: fp, bounds: bounds, flipped: true)
            == CGRect(x: 50, y: 0, width: 500, height: 124))
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter NotchFootprintTests`
Expected: FAIL — `NotchFootprint` not defined.

- [ ] **Step 3: Implement**

Create `Sources/OpenNotchKit/NotchFootprint.swift`:

```swift
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter NotchFootprintTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/OpenNotchKit/NotchFootprint.swift Tests/OpenNotchKitTests/NotchFootprintTests.swift
git commit -m "feat(kit): NotchFootprint — per-phase shape size + hit rect"
```

---

### Task 3: Static-window animation substrate (the M2.0 rewrite)

**Files:**
- Modify: `Sources/OpenNotch/NotchWindow.swift` (major rewrite of `NotchController`; `NotchWindow` loses the spring machinery)
- Create: `Sources/OpenNotch/PassthroughHostingView.swift`
- Modify: `Sources/OpenNotch/NotchShell.swift` (morph-driven rendering)

This task is AppKit/SwiftUI — no unit tests; verified by build + the manual DoD (Task 12). It intentionally also wires the Task 1 events (click/escape/drag) since the monitors and drag destination live in the same files.

**Interfaces:**
- Consumes: `NotchFootprint` (Task 2), extended `NotchStateMachine` (Task 1), existing `NotchViewModel`, `PluginRuntime`, `NowPlayingService`.
- Produces: `NotchViewModel` gains `var footprint: CGSize = .zero` and `var spring: Animation`. `NotchController` keeps `init(runtime:nowPlaying:)`, `show()`, `hide()` (Task 7 changes init to take a screen). `PassthroughHostingView` with `interactiveRect: () -> CGRect` and `onDragChange: ((Bool) -> Void)?`.

- [ ] **Step 1: Create `Sources/OpenNotch/PassthroughHostingView.swift`**

```swift
import AppKit
import SwiftUI

/// Hosting view for the oversized static panel. Mouse events outside the
/// visible notch shape fall through to whatever is behind the transparent
/// window region; file drags over the shape report in/out for the FSM.
final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    var interactiveRect: () -> CGRect = { .zero }
    var onDragChange: ((Bool) -> Void)?
    private var dragInside = false

    required init(rootView: Content) {
        super.init(rootView: rootView)
        registerForDraggedTypes([.fileURL])
    }

    @MainActor @preconcurrency required dynamic init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // `point` is in the superview's coordinate space.
        let local = convert(point, from: superview)
        guard interactiveRect().contains(local) else { return nil }
        return super.hitTest(point)
    }

    // M2 only expands on drag-hover; dropping is M4 (shelf). Return [] so the
    // drag is not accepted anywhere yet.
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        updateDrag(sender)
        return []
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        updateDrag(sender)
        return []
    }
    override func draggingExited(_ sender: NSDraggingInfo?) {
        if dragInside { dragInside = false; onDragChange?(false) }
    }

    private func updateDrag(_ sender: NSDraggingInfo) {
        let inside = interactiveRect().contains(convert(sender.draggingLocation, from: nil))
        if inside != dragInside {
            dragInside = inside
            onDragChange?(inside)
        }
    }
}
```

- [ ] **Step 2: Rewrite `Sources/OpenNotch/NotchShell.swift` rendering**

Keep `NotchPanelShape` and `QuickActionsColumn` exactly as they are. Replace `NotchViewModel` and `NotchShell` with:

```swift
/// Observable state for the shell. Held once by the controller and mutated in
/// place so SwiftUI animates transitions internally.
@Observable @MainActor final class NotchViewModel {
    var phase: NotchPhase = .collapsed
    var footprint: CGSize = .zero       // current shape size inside the fixed panel
    var widgets: [PluginWidget]
    var quickActions: [QuickAction] = []
    var topInset: CGFloat = 32
    var showAmbient = false
    var notchGap: CGFloat = 200
    @ObservationIgnored var compactLeading: AnyView?
    @ObservationIgnored var compactTrailing: AnyView?
    init(widgets: [PluginWidget]) { self.widgets = widgets }

    /// Island feel (spec M2.0): bouncy open, snappy close. Tuning knobs.
    var spring: Animation {
        isOpen ? .spring(response: 0.4, dampingFraction: 0.7)
               : .spring(response: 0.3, dampingFraction: 0.85)
    }
    var isOpen: Bool { phase == .expanded || phase == .pinned }
}

/// Content materializes with the morph: scale from the top + fade + blur.
private struct BlurModifier: ViewModifier {
    let radius: CGFloat
    func body(content: Content) -> some View { content.blur(radius: radius) }
}
private extension AnyTransition {
    static var notchContent: AnyTransition {
        .scale(scale: 0.85, anchor: .top)
            .combined(with: .opacity)
            .combined(with: .modifier(active: BlurModifier(radius: 6),
                                      identity: BlurModifier(radius: 0)))
    }
}

struct NotchShell: View {
    let model: NotchViewModel
    var body: some View {
        ZStack(alignment: .top) {
            NotchPanelShape(topRadius: 10, bottomRadius: 20)
                .fill(.black)
                .frame(width: model.footprint.width, height: model.footprint.height)
            content
                .frame(width: model.footprint.width, height: model.footprint.height,
                       alignment: .top)
                .clipped()
        }
        // One spring drives shape + content together — a single morphing blob.
        .animation(model.spring, value: model.footprint)
        .animation(model.spring, value: model.phase)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder private var content: some View {
        if model.isOpen {
            VStack(spacing: 0) {
                Color.clear.frame(height: model.topInset)
                HStack(alignment: .center, spacing: 12) {
                    ForEach(model.widgets) { $0.content }
                    if !model.quickActions.isEmpty {
                        Rectangle().fill(.white.opacity(0.12)).frame(width: 1, height: 60)
                        QuickActionsColumn(actions: model.quickActions)
                    }
                }
                .padding(.horizontal, 12).padding(.bottom, 8).padding(.top, 4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .transition(.notchContent)
        } else if model.showAmbient {
            HStack(spacing: 0) {
                model.compactLeading
                Spacer(minLength: model.notchGap)
                model.compactTrailing
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity)
        }
    }
}
```

- [ ] **Step 3: Rewrite `Sources/OpenNotch/NotchWindow.swift`**

Delete: the `frameSpring` property and `animation(forKey:)` override on `NotchWindow`, the free function `frameSpring(response:damping:)`, and in the controller: `hoverLocked`, `hoverUnlock`, `lockHover(for:)`, `expandedRect()`, `collapsedFrame()`, and all `animator().setFrame` calls. Replace the file with:

```swift
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

    private let panel: NotchWindow
    private let hostingView: PassthroughHostingView<NotchShell>
    private let model: NotchViewModel
    private let runtime: PluginRuntime
    private let nowPlaying: NowPlayingService
    private var stateMachine = NotchStateMachine()
    private var trackingArea: NSTrackingArea?
    private var pendingHoverOut: DispatchWorkItem?
    private var coveredByFullscreen = false
    private var fullscreenPoll: Timer?
    private var localMonitor: Any?
    private var globalMonitor: Any?

    init(runtime: PluginRuntime, nowPlaying: NowPlayingService) {
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

        if let inset = NSScreen.main?.safeAreaInsets.top, inset > 0 { model.topInset = inset }
        if let screen = NSScreen.main,
           let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
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
        guard let screen = NSScreen.main else {
            return CGRect(origin: .zero, size: panelSize)
        }
        return CGRect(x: screen.frame.midX - panelSize.width / 2,
                      y: screen.frame.maxY - panelSize.height,
                      width: panelSize.width, height: panelSize.height)
    }

    private func notchSize() -> CGSize {
        guard let screen = NSScreen.main else { return fallbackPillSize }
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

    private func observeFullscreen() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(evaluateFullscreen),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil)
        let poll = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.evaluateFullscreen() }
        }
        RunLoop.main.add(poll, forMode: .common)
        fullscreenPoll = poll
        evaluateFullscreen()
    }

    @objc private func evaluateFullscreen() {
        let covered = FullscreenDetector.coversNotch(currentWindows(),
                                                     mainDisplayFrame: mainDisplayFrameCG())
        guard covered != coveredByFullscreen else { return }
        coveredByFullscreen = covered
        transition(covered ? .enterFullscreen : .exitFullscreen)
    }

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
```

Notes for the implementer:
- The `.inVisibleRect` tracking option is gone on purpose: the tracking rect is now the *footprint*, not the whole view, and is reinstalled on every phase/footprint change.
- `transition(_:)` early-returns when the phase didn't change — monitors fire for every click anywhere, so this guard keeps no-op events cheap.
- The `clickOutside` local-monitor branch fires for clicks in our OTHER windows (e.g. Settings) — that correctly unpins.

- [ ] **Step 4: Build and fix compile errors**

Run: `swift build`
Expected: builds clean. (`NotchShell` no longer references `model.phase == .expanded` directly; `isOpen` covers pinned.)

- [ ] **Step 5: Smoke-run on hardware**

Run: `swift run OpenNotch` on the MacBook.
Verify quickly (full DoD comes later): hover expands with bounce; rapid hover in/out mid-animation retargets smoothly with **no loop and no dead zone**; click inside panel pins it (hover-out keeps it open); click on the desktop unpins; play/pause buttons still work; ambient bar appears when music plays; clicks pass through the transparent corners of the window region to apps behind.

- [ ] **Step 6: Commit**

```bash
git add Sources/OpenNotch/NotchWindow.swift Sources/OpenNotch/NotchShell.swift Sources/OpenNotch/PassthroughHostingView.swift
git commit -m "feat: static-window animation substrate — SwiftUI morph, hit-test passthrough, pin/drag/escape wiring"
```

---

### Task 4: Adapter path resolution (pure) + bundle-aware bridge

**Files:**
- Create: `Sources/OpenNotchKit/AdapterPaths.swift`
- Test: `Tests/OpenNotchKitTests/AdapterPathsTests.swift`
- Modify: `Sources/OpenNotch/AppDelegate.swift:78-80` (bridge construction)

**Interfaces:**
- Consumes: nothing.
- Produces: `AdapterPaths.Resolved` (`script: String`, `framework: String`, both absolute) and `AdapterPaths.resolve(bundleResourceURL: URL?, cwd: String, fileExists: (String) -> Bool) -> Resolved`. Bundle resources win when both files exist; otherwise fall back to `<cwd>/vendor/...` (dev mode under `swift run`).

- [ ] **Step 1: Write the failing tests**

Create `Tests/OpenNotchKitTests/AdapterPathsTests.swift`:

```swift
import Testing
import Foundation
@testable import OpenNotchKit

@Test func prefersBundleResourcesWhenPresent() {
    let r = AdapterPaths.resolve(bundleResourceURL: URL(fileURLWithPath: "/App/Contents/Resources"),
                                 cwd: "/repo",
                                 fileExists: { _ in true })
    #expect(r.script == "/App/Contents/Resources/mediaremote-adapter/bin/mediaremote-adapter.pl")
    #expect(r.framework == "/App/Contents/Resources/mediaremote-adapter/build/MediaRemoteAdapter.framework")
}

@Test func fallsBackToCwdWhenBundleFilesMissing() {
    let r = AdapterPaths.resolve(bundleResourceURL: URL(fileURLWithPath: "/App/Contents/Resources"),
                                 cwd: "/repo",
                                 fileExists: { _ in false })
    #expect(r.script == "/repo/vendor/mediaremote-adapter/bin/mediaremote-adapter.pl")
    #expect(r.framework == "/repo/vendor/mediaremote-adapter/build/MediaRemoteAdapter.framework")
}

@Test func fallsBackWhenNoBundleURL() {
    let r = AdapterPaths.resolve(bundleResourceURL: nil, cwd: "/repo", fileExists: { _ in true })
    #expect(r.script.hasPrefix("/repo/vendor/"))
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter AdapterPathsTests`
Expected: FAIL — `AdapterPaths` not defined.

- [ ] **Step 3: Implement**

Create `Sources/OpenNotchKit/AdapterPaths.swift`:

```swift
import Foundation

/// Locates the mediaremote-adapter script + framework: inside the app bundle's
/// Resources when packaged (Task 5's make-app.sh copies them there), else
/// relative to the working directory (dev mode: `swift run` from package root).
public enum AdapterPaths {
    public struct Resolved: Equatable {
        public let script: String
        public let framework: String
    }

    public static func resolve(bundleResourceURL: URL?, cwd: String,
                               fileExists: (String) -> Bool) -> Resolved {
        if let base = bundleResourceURL?.appendingPathComponent("mediaremote-adapter") {
            let script = base.appendingPathComponent("bin/mediaremote-adapter.pl").path
            let framework = base.appendingPathComponent("build/MediaRemoteAdapter.framework").path
            if fileExists(script), fileExists(framework) {
                return Resolved(script: script, framework: framework)
            }
        }
        return Resolved(script: cwd + "/vendor/mediaremote-adapter/bin/mediaremote-adapter.pl",
                        framework: cwd + "/vendor/mediaremote-adapter/build/MediaRemoteAdapter.framework")
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter AdapterPathsTests`
Expected: PASS

- [ ] **Step 5: Use it in `AppDelegate.applicationDidFinishLaunching`**

Replace the bridge construction in `Sources/OpenNotch/AppDelegate.swift`:

```swift
let paths = AdapterPaths.resolve(
    bundleResourceURL: Bundle.main.resourceURL,
    cwd: FileManager.default.currentDirectoryPath,
    fileExists: { FileManager.default.fileExists(atPath: $0) })
let bridge = MediaRemoteBridge(script: paths.script, framework: paths.framework)
bridge.start()
```

- [ ] **Step 6: Build + run to verify dev mode still works**

Run: `swift build && swift test`
Expected: builds, all tests pass. `swift run OpenNotch` still streams media (cwd fallback).

- [ ] **Step 7: Commit**

```bash
git add Sources/OpenNotchKit/AdapterPaths.swift Tests/OpenNotchKitTests/AdapterPathsTests.swift Sources/OpenNotch/AppDelegate.swift
git commit -m "feat(kit): AdapterPaths — bundle-first adapter resolution with cwd dev fallback"
```

---

### Task 5: App-bundle build script

**Files:**
- Create: `Scripts/make-app.sh` (executable)

**Interfaces:**
- Consumes: release build output, `vendor/mediaremote-adapter/`, `AdapterPaths` bundle-first resolution (Task 4).
- Produces: `build/OpenNotch.app` — ad-hoc signed, `LSUIElement`, adapter embedded under `Contents/Resources/mediaremote-adapter/`.

- [ ] **Step 1: Write the script**

Create `Scripts/make-app.sh`:

```bash
#!/bin/bash
# Builds a double-clickable OpenNotch.app from the SPM release build.
# The mediaremote-adapter (perl script + framework) is embedded in Resources;
# AdapterPaths resolves it from Bundle.main at runtime.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

APP="build/OpenNotch.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp .build/release/OpenNotch "$APP/Contents/MacOS/OpenNotch"
cp -R vendor/mediaremote-adapter "$APP/Contents/Resources/mediaremote-adapter"
# Trim non-runtime vendor files from the bundle.
rm -rf "$APP/Contents/Resources/mediaremote-adapter/.vscode" \
       "$APP/Contents/Resources/mediaremote-adapter/.git" 2>/dev/null || true

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>OpenNotch</string>
    <key>CFBundleIdentifier</key><string>cafe.notch.OpenNotch</string>
    <key>CFBundleName</key><string>OpenNotch</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>2.0.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# Ad-hoc signature (spec M5: no Developer ID yet).
codesign --force --deep --sign - "$APP"
echo "Built $APP"
```

- [ ] **Step 2: Make it executable and run it**

Run: `chmod +x Scripts/make-app.sh && ./Scripts/make-app.sh`
Expected: `Built build/OpenNotch.app`, `codesign` exits 0.

- [ ] **Step 3: Manual verification**

- `open build/OpenNotch.app` from Finder (NOT from the repo root shell — cd elsewhere first to prove cwd independence): status item appears, notch works, **now-playing streams** (proves bundle resolution).
- Settings ▸ General ▸ Launch at Login toggles without error while running from the bundle.

- [ ] **Step 4: Commit**

```bash
git add Scripts/make-app.sh
git commit -m "feat: make-app.sh — double-clickable ad-hoc-signed OpenNotch.app with embedded adapter"
```

---

### Task 6: AppKit↔CoreGraphics coordinate conversion (pure)

**Files:**
- Create: `Sources/OpenNotchKit/CoordinateSpaces.swift`
- Test: `Tests/OpenNotchKitTests/CoordinateSpacesTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `CoordinateSpaces.cgRect(fromAppKit: CGRect, primaryScreenHeight: CGFloat) -> CGRect`. AppKit global space has a bottom-left origin on the primary screen; CG (what `CGWindowListCopyWindowInfo` returns and `FullscreenDetector` consumes) has a top-left origin on the primary screen. Needed so per-display fullscreen detection (Task 7) can pass each screen's frame in CG space.

- [ ] **Step 1: Write the failing tests**

Create `Tests/OpenNotchKitTests/CoordinateSpacesTests.swift`:

```swift
import Testing
import CoreGraphics
@testable import OpenNotchKit

@Test func primaryScreenFrameMapsToOrigin() {
    // Primary screen 1728x1117 in AppKit is origin (0,0) size-identical in CG.
    let appKit = CGRect(x: 0, y: 0, width: 1728, height: 1117)
    #expect(CoordinateSpaces.cgRect(fromAppKit: appKit, primaryScreenHeight: 1117)
            == CGRect(x: 0, y: 0, width: 1728, height: 1117))
}

@Test func screenAbovePrimaryGetsNegativeCGY() {
    // External display sitting on top of the primary in AppKit space.
    let appKit = CGRect(x: 100, y: 1117, width: 2560, height: 1440)
    #expect(CoordinateSpaces.cgRect(fromAppKit: appKit, primaryScreenHeight: 1117)
            == CGRect(x: 100, y: -1440, width: 2560, height: 1440))
}

@Test func windowInsidePrimaryFlipsY() {
    // A 800x600 window whose AppKit origin is y=100 on a 1117-tall primary:
    // its top edge is at appKit maxY=700 → CG y = 1117 - 700 = 417.
    let appKit = CGRect(x: 50, y: 100, width: 800, height: 600)
    #expect(CoordinateSpaces.cgRect(fromAppKit: appKit, primaryScreenHeight: 1117)
            == CGRect(x: 50, y: 417, width: 800, height: 600))
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter CoordinateSpacesTests`
Expected: FAIL — `CoordinateSpaces` not defined.

- [ ] **Step 3: Implement**

Create `Sources/OpenNotchKit/CoordinateSpaces.swift`:

```swift
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter CoordinateSpacesTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/OpenNotchKit/CoordinateSpaces.swift Tests/OpenNotchKitTests/CoordinateSpacesTests.swift
git commit -m "feat(kit): CoordinateSpaces — AppKit-to-CG global rect conversion"
```

---

### Task 7: Multi-display — one controller per screen

**Files:**
- Create: `Sources/OpenNotch/DisplayCoordinator.swift`
- Modify: `Sources/OpenNotch/NotchWindow.swift` (`NotchController` takes a screen; add `tearDown()`; per-screen fullscreen frame)
- Modify: `Sources/OpenNotch/AppDelegate.swift` (own a coordinator instead of one controller)

AppKit — manual DoD. No unit tests (all pure parts already extracted).

**Interfaces:**
- Consumes: `CoordinateSpaces` (Task 6), `NotchController` (Task 3).
- Produces: `NotchController.init(screen: NSScreen, runtime: PluginRuntime, nowPlaying: NowPlayingService)`, `NotchController.tearDown()`. `DisplayCoordinator(runtime:nowPlaying:)` builds one controller per `NSScreen.screens` entry and rebuilds on screen-parameter changes.

- [ ] **Step 1: Parameterize `NotchController` by screen**

In `Sources/OpenNotch/NotchWindow.swift`:

1. Add `private let screen: NSScreen` and change the initializer signature to `init(screen: NSScreen, runtime: PluginRuntime, nowPlaying: NowPlayingService)`, setting `self.screen = screen` first.
2. Replace **every** `NSScreen.main` with `screen` (panelFrame, notchSize, the two `init` blocks reading `safeAreaInsets`/auxiliary areas, `mainDisplayFrameCG`).
3. Replace `mainDisplayFrameCG()` with a per-screen CG frame:

```swift
    /// This screen's frame in CG (top-left-origin) coordinates, matching the
    /// window bounds returned by CGWindowListCopyWindowInfo.
    private func screenFrameCG() -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CoordinateSpaces.cgRect(fromAppKit: screen.frame,
                                       primaryScreenHeight: primaryHeight)
    }
```

and update `evaluateFullscreen()` to use it:

```swift
        let covered = FullscreenDetector.coversNotch(currentWindows(),
                                                     mainDisplayFrame: screenFrameCG())
```

4. Add teardown (the coordinator rebuilds controllers on screen changes; leaked monitors/timers would double-fire):

```swift
    func tearDown() {
        fullscreenPoll?.invalidate()
        fullscreenPoll = nil
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        localMonitor = nil
        globalMonitor = nil
        pendingHoverOut?.cancel()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        panel.orderOut(nil)
    }
```

- [ ] **Step 2: Create `Sources/OpenNotch/DisplayCoordinator.swift`**

```swift
import AppKit
import OpenNotchKit

/// Owns one NotchController per attached display (notch shape on the built-in
/// screen, pill fallback elsewhere — NotchGeometry decides per screen) and
/// rebuilds the set when displays change (lid, monitor plug, resolution).
@MainActor
final class DisplayCoordinator {
    private let runtime: PluginRuntime
    private let nowPlaying: NowPlayingService
    private var controllers: [NotchController] = []
    private var observer: NSObjectProtocol?

    init(runtime: PluginRuntime, nowPlaying: NowPlayingService) {
        self.runtime = runtime
        self.nowPlaying = nowPlaying
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.rebuild() }
        }
        rebuild()
    }

    private func rebuild() {
        controllers.forEach { $0.tearDown() }
        controllers = NSScreen.screens.map { screen in
            let controller = NotchController(screen: screen, runtime: runtime,
                                             nowPlaying: nowPlaying)
            controller.show()
            return controller
        }
    }
}
```

- [ ] **Step 3: Rewire `AppDelegate`**

In `Sources/OpenNotch/AppDelegate.swift`, replace the `notch` property and construction:

```swift
    private var displays: DisplayCoordinator?
```

and in `applicationDidFinishLaunching`, replace

```swift
        let notch = NotchController(runtime: runtime, nowPlaying: host.nowPlaying)
        notch.show()
        ...
        self.notch = notch
```

with

```swift
        self.displays = DisplayCoordinator(runtime: runtime, nowPlaying: host.nowPlaying)
```

(remove the old `notch` property entirely).

- [ ] **Step 4: Build + manual verification**

Run: `swift build && swift run OpenNotch`

- Built-in display: notch behaves as before.
- Attach an external display: a pill appears top-center on it; hover expands it there.
- Unplug the display / close the lid: controllers rebuild without crash or duplicate panels (check Mission Control for strays).
- Fullscreen a video on the external display only → the external pill hides, the built-in notch stays.

- [ ] **Step 5: Commit**

```bash
git add Sources/OpenNotch/DisplayCoordinator.swift Sources/OpenNotch/NotchWindow.swift Sources/OpenNotch/AppDelegate.swift
git commit -m "feat: multi-display — per-screen NotchController via DisplayCoordinator, per-screen fullscreen detection"
```

---

### Task 8: Event-driven fullscreen triggers + adaptive poll

**Files:**
- Modify: `Sources/OpenNotch/NotchWindow.swift` (`observeFullscreen`, new suspend/resume)

AppKit — manual DoD.

**Interfaces:**
- Consumes: existing `evaluateFullscreen()` (Task 3/7 version).
- Produces: nothing new externally; the 1s poll pauses while the screen is asleep or locked.

- [ ] **Step 1: Add notification triggers and poll gating**

In `NotchController`, replace `observeFullscreen()` and add the gate:

```swift
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
```

Also extend `tearDown()` (Task 7) with:

```swift
        DistributedNotificationCenter.default().removeObserver(self)
```

- [ ] **Step 2: Build + manual verification**

Run: `swift build && swift run OpenNotch`

- Native fullscreen (e.g. Safari ⌃⌘F): notch hides **immediately** (no up-to-1s lag — the space-change notification fired).
- ⌘Tab to another app and back: no flicker, no false hides.
- YouTube in-window fullscreen in Chrome: still hides within ~1s (poll fallback).
- Lock screen (⌃⌘Q), unlock: notch returns correctly.

- [ ] **Step 3: Commit**

```bash
git add Sources/OpenNotch/NotchWindow.swift
git commit -m "feat: event-driven fullscreen triggers; suspend poll while locked/asleep"
```

---

### Task 9: Bridge supervision — restart policy + media-unavailable state

**Files:**
- Create: `Sources/OpenNotchKit/RestartPolicy.swift`
- Test: `Tests/OpenNotchKitTests/RestartPolicyTests.swift`
- Modify: `Sources/OpenNotchKit/PluginAPI.swift` (`NowPlayingService` gains `isAvailable`)
- Modify: `Sources/OpenNotch/MediaRemoteBridge.swift` (termination handler, restart, availability)
- Modify: `Sources/OpenNotchKit/NowPlayingView.swift` (unavailable state)
- Modify: existing test fakes (`Tests/OpenNotchKitTests/MediaPluginTests.swift`, `Tests/OpenNotchKitTests/NowPlayingReactivityTests.swift`, any other `NowPlayingService` fake) — add `isAvailable`.

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `RestartPolicy` (kit): `mutating func recordFailure(at: Date) -> Decision` where `Decision` is `.restart(after: TimeInterval)` or `.giveUp`; `mutating func recordSuccess()`. Give up on the 3rd failure within 60 seconds (spec M2.4); backoff 1s then 2s.
  - `NowPlayingService` gains `var isAvailable: Bool { get }` (protocol requirement; `true` in healthy operation).

- [ ] **Step 1: Write the failing tests**

Create `Tests/OpenNotchKitTests/RestartPolicyTests.swift`:

```swift
import Testing
import Foundation
@testable import OpenNotchKit

private let t0 = Date(timeIntervalSinceReferenceDate: 0)

@Test func backsOffThenGivesUpOnThirdRapidFailure() {
    var policy = RestartPolicy()
    #expect(policy.recordFailure(at: t0) == .restart(after: 1))
    #expect(policy.recordFailure(at: t0.addingTimeInterval(5)) == .restart(after: 2))
    #expect(policy.recordFailure(at: t0.addingTimeInterval(10)) == .giveUp)
}

@Test func oldFailuresExpireAfterAMinute() {
    var policy = RestartPolicy()
    _ = policy.recordFailure(at: t0)
    _ = policy.recordFailure(at: t0.addingTimeInterval(5))
    // 61s after the first failure: only the second is still in-window.
    #expect(policy.recordFailure(at: t0.addingTimeInterval(61)) == .restart(after: 2))
}

@Test func successResetsTheWindow() {
    var policy = RestartPolicy()
    _ = policy.recordFailure(at: t0)
    _ = policy.recordFailure(at: t0.addingTimeInterval(1))
    policy.recordSuccess()
    #expect(policy.recordFailure(at: t0.addingTimeInterval(2)) == .restart(after: 1))
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter RestartPolicyTests`
Expected: FAIL — `RestartPolicy` not defined.

- [ ] **Step 3: Implement `RestartPolicy`**

Create `Sources/OpenNotchKit/RestartPolicy.swift`:

```swift
import Foundation

/// Decides whether a crashed adapter stream should be restarted. Three
/// failures within a minute means something is systematically broken (e.g.
/// macOS changed the MediaRemote rules) — give up and surface "unavailable"
/// instead of crash-looping a perl process forever.
public struct RestartPolicy: Sendable {
    public enum Decision: Equatable, Sendable {
        case restart(after: TimeInterval)
        case giveUp
    }

    private var failures: [Date] = []
    private let window: TimeInterval = 60
    private let maxFailures = 3

    public init() {}

    public mutating func recordFailure(at now: Date) -> Decision {
        failures = failures.filter { now.timeIntervalSince($0) < window }
        failures.append(now)
        if failures.count >= maxFailures { return .giveUp }
        return .restart(after: pow(2, Double(failures.count - 1)))   // 1s, 2s
    }

    public mutating func recordSuccess() { failures = [] }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter RestartPolicyTests`
Expected: PASS

- [ ] **Step 5: Add `isAvailable` to the service protocol and all fakes**

In `Sources/OpenNotchKit/PluginAPI.swift`, add to `NowPlayingService`:

```swift
@MainActor public protocol NowPlayingService: AnyObject, Observable {
    var current: NowPlayingInfo? { get }
    /// False when the host's media backend is down (adapter kept crashing).
    var isAvailable: Bool { get }
    func play(); func pause(); func toggle()
    func next(); func previous()
    func seek(to time: TimeInterval)
}
```

Then add `var isAvailable: Bool = true` to every fake `NowPlayingService` in the test suite (search: `grep -rn "NowPlayingService" Tests/`). Run `swift build` — the compiler lists every non-conforming fake.

- [ ] **Step 6: Wire supervision into `MediaRemoteBridge`**

In `Sources/OpenNotch/MediaRemoteBridge.swift`:

1. Add properties:

```swift
    public private(set) var isAvailable = true
    @ObservationIgnored private var restartPolicy = RestartPolicy()
    @ObservationIgnored private var stopping = false
```

2. In `start()`, before `try? p.run()`, add the termination handler; and record success when a line parses:

```swift
        p.terminationHandler = { [weak self] _ in
            Task { @MainActor in self?.streamEnded() }
        }
```

and change the publish line inside the readability handler from

```swift
            if let latest { Task { @MainActor in self.current = latest } }
```

to

```swift
            if let latest {
                Task { @MainActor in
                    self.restartPolicy.recordSuccess()
                    self.isAvailable = true
                    self.current = latest
                }
            }
```

3. Add the restart logic:

```swift
    private func streamEnded() {
        stream = nil
        guard !stopping else { return }
        switch restartPolicy.recordFailure(at: Date()) {
        case .restart(let delay):
            NSLog("OpenNotch: adapter stream died; restarting in \(delay)s")
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.start()
            }
        case .giveUp:
            NSLog("OpenNotch: adapter stream keeps dying; media marked unavailable")
            current = nil
            isAvailable = false
        }
    }
```

4. In `stop()`, set `stopping = true` before `stream?.terminate()` (manual stop must not trigger a restart).

- [ ] **Step 7: Show the unavailable state in `NowPlayingView`**

In `Sources/OpenNotchKit/NowPlayingView.swift`, at the top of `body`:

```swift
        let info = service.current
        if !service.isAvailable {
            return AnyView(
                Text("Media unavailable")
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
                    .frame(width: 220, height: 60)
            )
        }
```

(and wrap the existing return in `AnyView(...)` so both branches type-check, or restructure with `@ViewBuilder` — implementer's choice, keep it small.)

- [ ] **Step 8: Run all tests + manual check**

Run: `swift test`
Expected: PASS (fakes updated).

Manual: `swift run OpenNotch`, then `pkill -f mediaremote-adapter` — stream restarts (music keeps updating after ~1s). Kill it 3 times rapidly — panel shows "Media unavailable" instead of frozen stale data.

- [ ] **Step 9: Commit**

```bash
git add Sources/OpenNotchKit Sources/OpenNotch Tests
git commit -m "feat: adapter supervision — RestartPolicy backoff, media-unavailable state"
```

---

### Task 10: Live progress + scrubber

**Files:**
- Modify: `Sources/OpenNotchKit/NowPlayingInfo.swift` (add `timestamp`)
- Create: `Sources/OpenNotchKit/PlaybackProgress.swift`
- Test: `Tests/OpenNotchKitTests/PlaybackProgressTests.swift`
- Modify: `Sources/OpenNotch/MediaRemoteBridge.swift` (stamp on publish; de-dup)
- Modify: `Sources/OpenNotchKit/NowPlayingView.swift` (progress bar + drag-to-seek)

**Interfaces:**
- Consumes: `NowPlayingInfo`, `NowPlayingService.seek(to:)`.
- Produces:
  - `NowPlayingInfo.timestamp: Date?` — when the host received this snapshot (set by the bridge, `nil` from the pure parser).
  - `PlaybackProgress.position(info: NowPlayingInfo, at: Date) -> TimeInterval?` — `elapsed` extrapolated by wall-clock while playing, clamped to `0...duration`; `nil` when `elapsed` is nil.

- [ ] **Step 1: Add the `timestamp` field**

In `Sources/OpenNotchKit/NowPlayingInfo.swift`, add `public var timestamp: Date?` alongside the other properties and `timestamp: Date? = nil` to the memberwise init (last parameter).

- [ ] **Step 2: Write the failing tests**

Create `Tests/OpenNotchKitTests/PlaybackProgressTests.swift`:

```swift
import Testing
import Foundation
@testable import OpenNotchKit

private let t0 = Date(timeIntervalSinceReferenceDate: 1000)

@Test func extrapolatesWhilePlaying() {
    let info = NowPlayingInfo(isPlaying: true, elapsed: 30, duration: 200, timestamp: t0)
    #expect(PlaybackProgress.position(info: info, at: t0.addingTimeInterval(5)) == 35)
}

@Test func frozenWhilePaused() {
    let info = NowPlayingInfo(isPlaying: false, elapsed: 30, duration: 200, timestamp: t0)
    #expect(PlaybackProgress.position(info: info, at: t0.addingTimeInterval(60)) == 30)
}

@Test func clampsToDuration() {
    let info = NowPlayingInfo(isPlaying: true, elapsed: 195, duration: 200, timestamp: t0)
    #expect(PlaybackProgress.position(info: info, at: t0.addingTimeInterval(60)) == 200)
}

@Test func nilElapsedGivesNil() {
    let info = NowPlayingInfo(isPlaying: true, timestamp: t0)
    #expect(PlaybackProgress.position(info: info, at: t0) == nil)
}

@Test func missingTimestampReturnsRawElapsed() {
    let info = NowPlayingInfo(isPlaying: true, elapsed: 30, duration: 200)
    #expect(PlaybackProgress.position(info: info, at: t0) == 30)
}
```

Note: the `NowPlayingInfo` memberwise init has defaults for every parameter — these calls compile once `timestamp` is added.

- [ ] **Step 3: Run tests to verify they fail**

Run: `swift test --filter PlaybackProgressTests`
Expected: FAIL — `PlaybackProgress` not defined.

- [ ] **Step 4: Implement**

Create `Sources/OpenNotchKit/PlaybackProgress.swift`:

```swift
import Foundation

/// Extrapolates the display position of the progress bar between adapter
/// snapshots — the adapter only streams on state changes, so while a track
/// plays the UI advances `elapsed` by wall-clock locally (no polling).
public enum PlaybackProgress {
    public static func position(info: NowPlayingInfo, at now: Date) -> TimeInterval? {
        guard let elapsed = info.elapsed else { return nil }
        guard info.isPlaying, let timestamp = info.timestamp else { return elapsed }
        let position = elapsed + now.timeIntervalSince(timestamp)
        if let duration = info.duration { return min(max(position, 0), duration) }
        return max(position, 0)
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter PlaybackProgressTests`
Expected: PASS

- [ ] **Step 6: Stamp + de-dup in the bridge**

In `Sources/OpenNotch/MediaRemoteBridge.swift`, add a raw-snapshot property:

```swift
    @ObservationIgnored private var lastRaw: NowPlayingInfo?
```

and replace the publish block (from Task 9 Step 6) with:

```swift
            if let latest {
                Task { @MainActor in
                    self.restartPolicy.recordSuccess()
                    self.isAvailable = true
                    // De-dup: the --no-diff stream re-sends full snapshots
                    // (incl. ~80KB artwork); identical payloads must not
                    // re-trigger every observer.
                    guard latest != self.lastRaw else { return }
                    self.lastRaw = latest
                    var stamped = latest
                    stamped.timestamp = Date()
                    self.current = stamped
                }
            }
```

- [ ] **Step 7: Add the progress bar to `NowPlayingView`**

In `Sources/OpenNotchKit/NowPlayingView.swift`, add below `EqualizerBars`:

```swift
/// Progress bar with drag-to-seek. Advances by wall clock between snapshots
/// (PlaybackProgress); a drag previews the target locally and seeks on release.
struct ProgressBar: View {
    let info: NowPlayingInfo
    let seek: (TimeInterval) -> Void
    @State private var dragTarget: TimeInterval?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let duration = info.duration ?? 0
            let position = dragTarget
                ?? PlaybackProgress.position(info: info, at: context.date) ?? 0
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.2))
                    Capsule().fill(.white)
                        .frame(width: duration > 0
                               ? geo.size.width * min(position / duration, 1) : 0)
                }
                .contentShape(Rectangle().inset(by: -6))   // fat touch target
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard duration > 0 else { return }
                            let fraction = min(max(value.location.x / geo.size.width, 0), 1)
                            dragTarget = duration * fraction
                        }
                        .onEnded { _ in
                            if let target = dragTarget { seek(target) }
                            dragTarget = nil
                        })
            }
            .frame(height: 3)
        }
        .frame(height: 3)
    }
}
```

and render it in `NowPlayingView.body` inside the text `VStack`, between the artist line and the transport buttons:

```swift
                if let info, info.duration != nil {
                    ProgressBar(info: info, seek: vm.seek)
                        .padding(.top, 4)
                }
```

- [ ] **Step 8: Run tests + manual check**

Run: `swift test` → PASS.
Manual: play a song, expand — the bar advances smoothly every 0.5s without adapter events; pause freezes it; dragging the bar seeks (audible jump).

- [ ] **Step 9: Commit**

```bash
git add Sources/OpenNotchKit Sources/OpenNotch Tests
git commit -m "feat: live playback progress + drag-to-seek scrubber; de-dup adapter snapshots"
```

---

### Task 11: Real source badge (playing app's icon)

**Files:**
- Modify: `Sources/OpenNotchKit/NowPlayingInfo.swift` (add `sourceBundleId`)
- Modify: `Sources/OpenNotchKit/NowPlayingParser.swift` (parse it)
- Test: `Tests/OpenNotchKitTests/NowPlayingParserTests.swift`
- Modify: `Sources/OpenNotchKit/NowPlayingView.swift` (badge uses an icon lookup)
- Modify: `Sources/OpenNotchKit/MediaPlugin.swift` (supply lookup from `host.installedApps()`)

**Interfaces:**
- Consumes: `PluginHost.installedApps()` (existing).
- Produces: `NowPlayingInfo.sourceBundleId: String?`; `NowPlayingView.init(service: NowPlayingService, appIcon: @escaping (String) -> Data? = { _ in nil })`.

- [ ] **Step 1: Write the failing parser test**

Append to `Tests/OpenNotchKitTests/NowPlayingParserTests.swift`:

```swift
@Test func parsesSourceBundleId() {
    let line = #"{"title":"Song","playing":true,"bundleIdentifier":"com.apple.Music"}"#
    let info = NowPlayingParser.parse(line: line)
    #expect(info?.sourceBundleId == "com.apple.Music")
}

@Test func missingBundleIdentifierIsNil() {
    let info = NowPlayingParser.parse(line: #"{"title":"Song","playing":true}"#)
    #expect(info?.sourceBundleId == nil)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter NowPlayingParserTests`
Expected: FAIL — `sourceBundleId` not defined.

- [ ] **Step 3: Implement**

- `NowPlayingInfo.swift`: add `public var sourceBundleId: String?` + init parameter `sourceBundleId: String? = nil`.
- `NowPlayingParser.swift`: add `info.sourceBundleId = obj["bundleIdentifier"] as? String` with the other field assignments.

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter NowPlayingParserTests`
Expected: PASS

- [ ] **Step 5: Use it for the badge**

In `Sources/OpenNotchKit/NowPlayingView.swift`, change the init:

```swift
    private let appIcon: (String) -> Data?
    public init(service: NowPlayingService,
                appIcon: @escaping (String) -> Data? = { _ in nil }) {
        self.service = service
        self.vm = NowPlayingViewModel(service: service)
        self.appIcon = appIcon
    }
```

Replace the hardcoded badge (`Image(systemName: "music.note")` with red circle background) with:

```swift
                badge(for: info)
                    .offset(x: 5, y: 5)
```

and add:

```swift
    @ViewBuilder private func badge(for info: NowPlayingInfo?) -> some View {
        if let id = info?.sourceBundleId, let data = appIcon(id),
           let img = NSImage(data: data) {
            Image(nsImage: img).resizable()
                .frame(width: 19, height: 19)
                .clipShape(Circle())
                .overlay(Circle().stroke(.black, lineWidth: 1.5))
        } else {
            Image(systemName: "music.note")
                .font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                .frame(width: 19, height: 19)
                .background(Circle().fill(.red))
                .overlay(Circle().stroke(.black, lineWidth: 1.5))
        }
    }
```

In `Sources/OpenNotchKit/MediaPlugin.swift`, supply the lookup (public API only — the keystone rule holds):

```swift
    public func widgets() -> [PluginWidget] {
        let host = self.host
        return [PluginWidget(id: "now-playing", size: .wide,
                             content: AnyView(NowPlayingView(
                                service: host.nowPlaying,
                                appIcon: { id in
                                    host.installedApps()
                                        .first(where: { $0.bundleId == id })?.iconData
                                })))]
    }
```

- [ ] **Step 6: Run tests + manual check**

Run: `swift test` → PASS.
Manual: play in Music/Spotify → badge shows that app's icon; a source not under `/Applications` falls back to the red music note.

- [ ] **Step 7: Commit**

```bash
git add Sources/OpenNotchKit Tests
git commit -m "feat: source badge shows the playing app's real icon"
```

---

### Task 12: Cross-cutting sweep — os.Logger, app-cache invalidation

**Files:**
- Modify: `Sources/OpenNotch/MediaRemoteBridge.swift`, `Sources/OpenNotch/AppDelegate.swift`, `Sources/OpenNotch/SettingsWindow.swift` (NSLog → Logger; cache invalidation)

**Interfaces:**
- Consumes: everything above.
- Produces: `AppHost.invalidateAppCache()`.

- [ ] **Step 1: Replace NSLog with os.Logger**

In each file that calls `NSLog`, add `import os` and a logger:

```swift
private let log = Logger(subsystem: "cafe.notch", category: "media")   // per-file category: "media", "host", "settings"
```

Replace every `NSLog("OpenNotch: ...")` with `log.error("...")` (or `.notice` for non-errors like the restart message). Search: `grep -rn NSLog Sources/`. Expected categories: `media` (bridge), `host` (AppDelegate/AppHost), `settings` (SettingsWindow).

- [ ] **Step 2: Invalidate the installed-apps cache when Settings opens**

In `AppHost`, add:

```swift
    func invalidateAppCache() { cachedApps = nil }
```

In `AppDelegate.openSettings()`, invalidate before reading:

```swift
    @objc private func openSettings() {
        host?.invalidateAppCache()
        settings.show(store: launcherStore, installedApps: host?.installedApps() ?? [])
    }
```

(This closes the spec's "newly-installed app requires relaunch" gap: opening Settings re-scans.)

- [ ] **Step 3: Build, test, verify no NSLog remains**

Run: `swift build && swift test && { grep -rn NSLog Sources/ || echo "clean"; }`
Expected: build + tests green; `clean`.

- [ ] **Step 4: Commit**

```bash
git add Sources/OpenNotch
git commit -m "chore: os.Logger everywhere; re-scan installed apps on Settings open"
```

---

### Task 13: README + manual DoD checklist for M2

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Update the README**

- Running section: add `./Scripts/make-app.sh` → `build/OpenNotch.app` as the packaged path; keep `swift run OpenNotch` as dev mode.
- Replace the M1 DoD checklist with the M2 one:

```markdown
## Definition of Done (M2) — manual checklist

Walk this on a physical MacBook with a notch, running `build/OpenNotch.app`
launched from Finder (not the repo root):

- [ ] Hover notch → expands with a bouncy spring; hover out → snappy close.
- [ ] Rapid hover in/out mid-animation retargets smoothly — no loop, no dead zone.
- [ ] Clicks land on apps behind the transparent window margins.
- [ ] Click the notch/panel → pins open (hover-out keeps it open); click
      anywhere else → unpins.
- [ ] Drag a file over the notch → panel expands; drag away → collapses.
- [ ] Play/pause/next/previous work; progress bar advances live; drag it to seek.
- [ ] Source badge shows the playing app's icon.
- [ ] `pkill -f mediaremote-adapter` → stream recovers; kill it 3× fast →
      "Media unavailable" (no frozen stale card).
- [ ] External display: pill appears there; fullscreen on one display hides
      only that display's notch/pill.
- [ ] Unplug display / close lid → panels rebuild, no strays, no crash.
- [ ] Native fullscreen hides the notch immediately; YouTube in-window
      fullscreen hides it within ~1s; exiting restores it.
- [ ] Lock screen + unlock → notch returns.
- [ ] Launch at Login works from the bundled app.
```

- [ ] **Step 2: Walk the checklist**

Run `./Scripts/make-app.sh`, launch from Finder, walk every box. Fix regressions before committing (each fix goes in the task that owns the file).

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: M2 README — packaged app instructions + M2 manual DoD checklist"
```

---

## After M2

M2 complete = all tasks committed + the Task 13 checklist walked green. Then:

1. Merge/PR per the repo's flow.
2. Write the **M3 plan** (plugin platform) from the spec with the writing-plans skill. Start M3 with the spec's risk-#1 spike: prove a de-quarantined `.notchplugin` bundle dlopens on the current macOS **before** building the loader.
3. M4 and M5 plans follow the same pattern, one per milestone.
