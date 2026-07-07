import SwiftUI
import Observation
import OpenNotchKit

/// The hardware-notch silhouette: full-width top edge that flares into the screen
/// with a small *concave* (inverse) radius at the top corners, and convex rounded
/// bottom corners — so the panel reads as an extension of the physical notch.
struct NotchPanelShape: Shape {
    var topRadius: CGFloat = 10      // inverse (concave) flare
    var bottomRadius: CGFloat = 22   // convex round
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height, tr = topRadius, br = bottomRadius
        var p = Path()
        p.move(to: CGPoint(x: 0, y: 0))
        p.addLine(to: CGPoint(x: w, y: 0))                                   // top edge (full width)
        p.addQuadCurve(to: CGPoint(x: w - tr, y: tr),                        // concave top-right flare
                       control: CGPoint(x: w - tr, y: 0))
        p.addLine(to: CGPoint(x: w - tr, y: h - br))                         // right wall
        p.addQuadCurve(to: CGPoint(x: w - tr - br, y: h),                    // convex bottom-right
                       control: CGPoint(x: w - tr, y: h))
        p.addLine(to: CGPoint(x: tr + br, y: h))                            // bottom edge
        p.addQuadCurve(to: CGPoint(x: tr, y: h - br),                        // convex bottom-left
                       control: CGPoint(x: tr, y: h))
        p.addLine(to: CGPoint(x: tr, y: tr))                                 // left wall
        p.addQuadCurve(to: CGPoint(x: 0, y: 0),                              // concave top-left flare
                       control: CGPoint(x: tr, y: 0))
        p.closeSubpath()
        return p
    }
}

/// Observable state for the shell. Held once by the controller and mutated in
/// place so SwiftUI animates transitions internally.
@Observable @MainActor final class NotchViewModel {
    var phase: NotchPhase = .collapsed
    var footprint: CGSize = .zero       // current shape size inside the fixed panel
    var widgets: [PluginWidget]
    var quickActions: [QuickAction] = []
    var topInset: CGFloat = 32          // menubar/notch height reserved at the top
    var neckWidth: CGFloat = 200        // notch-width neck kept through the menubar strip
    // Ambient bar (collapsed + has media): compact views flank the physical notch.
    var showAmbient = false
    var notchGap: CGFloat = 200         // physical notch width left transparent in the middle
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

/// The expanded panel's right column: one pill per plugin-contributed QuickAction.
private struct QuickActionsColumn: View {
    let actions: [QuickAction]
    var body: some View {
        VStack(spacing: 8) {
            ForEach(actions) { action in
                Button(action: action.action) {
                    HStack(spacing: 8) {
                        icon(for: action)
                        Text(action.title)
                            .foregroundStyle(.white).font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .frame(width: 132)
                    .background(.white.opacity(0.08), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
    @ViewBuilder private func icon(for action: QuickAction) -> some View {
        if let data = action.iconData, let img = NSImage(data: data) {
            Image(nsImage: img).resizable().frame(width: 18, height: 18)
        } else {
            Image(systemName: action.systemImage).foregroundStyle(.white).font(.system(size: 13))
        }
    }
}

/// The expanded silhouette: a notch-width neck through the menubar strip that
/// flares out with convex shoulders into the full-width, rounded-bottom panel
/// below. So the panel hangs *below* the menubar and never paints over the
/// menubar items flanking the notch. Collapsed/ambient footprints (no taller
/// than the menubar) fall back to the plain notch shape at full width.
struct ExpandingNotchShape: Shape {
    var neckWidth: CGFloat
    var menuBarHeight: CGFloat
    var bottomRadius: CGFloat = 20
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        guard h > menuBarHeight + 1 else {
            return NotchPanelShape(topRadius: 10, bottomRadius: 20).path(in: rect)
        }
        let midX = rect.midX
        let halfN = min(neckWidth, w) / 2
        let m = menuBarHeight
        let br = min(bottomRadius, (h - m) / 2)
        let drop = min(14, h - m - br)          // shoulder vertical drop below the menubar
        var p = Path()
        p.move(to: CGPoint(x: midX - halfN, y: 0))
        p.addLine(to: CGPoint(x: midX + halfN, y: 0))                       // neck top edge
        p.addLine(to: CGPoint(x: midX + halfN, y: m))                       // neck right wall
        p.addQuadCurve(to: CGPoint(x: w, y: m + drop),                      // right shoulder flare
                       control: CGPoint(x: w, y: m))
        p.addLine(to: CGPoint(x: w, y: h - br))                             // right wall
        p.addQuadCurve(to: CGPoint(x: w - br, y: h), control: CGPoint(x: w, y: h))
        p.addLine(to: CGPoint(x: br, y: h))                                 // bottom edge
        p.addQuadCurve(to: CGPoint(x: 0, y: h - br), control: CGPoint(x: 0, y: h))
        p.addLine(to: CGPoint(x: 0, y: m + drop))                           // left wall
        p.addQuadCurve(to: CGPoint(x: midX - halfN, y: m),                  // left shoulder flare
                       control: CGPoint(x: 0, y: m))
        p.addLine(to: CGPoint(x: midX - halfN, y: 0))                       // neck left wall
        p.closeSubpath()
        return p
    }
}

struct NotchShell: View {
    let model: NotchViewModel
    var body: some View {
        let shape = ExpandingNotchShape(neckWidth: model.neckWidth, menuBarHeight: model.topInset)
        ZStack(alignment: .top) {
            shape.fill(.black)
                .frame(width: model.footprint.width, height: model.footprint.height)
            content
                .frame(width: model.footprint.width, height: model.footprint.height,
                       alignment: .top)
                .clipShape(shape)
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
                .padding(.horizontal, 8).padding(.bottom, 8).padding(.top, 14)
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
