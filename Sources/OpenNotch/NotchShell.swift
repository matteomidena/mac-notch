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
/// place so SwiftUI animates the transition internally (rather than us replacing
/// the whole rootView, which would not animate smoothly).
@Observable @MainActor final class NotchViewModel {
    var phase: NotchPhase = .collapsed
    var widgets: [PluginWidget]
    var topInset: CGFloat = 32          // menubar/notch height reserved at the top
    init(widgets: [PluginWidget]) { self.widgets = widgets }
}

/// Placeholder shortcuts column (right side of the expanded panel). These are
/// visual stand-ins for future plugin-contributed quick actions, not working
/// features. ponytail: replace with real plugin widgets when the compact/quick-
/// action API lands.
private struct QuickActionsPlaceholder: View {
    var body: some View {
        HStack(spacing: 10) {
            VStack(spacing: 8) {
                pill("Spotify")
                pill("Shortcut")
            }
            VStack(spacing: 4) {
                Image(systemName: "video.fill").font(.system(size: 16))
                Text("Mirror").font(.system(size: 10))
            }
            .foregroundStyle(.white.opacity(0.85))
            .frame(width: 66, height: 66)
            .background(.white.opacity(0.08), in: Circle())
        }
    }
    private func pill(_ title: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles").foregroundStyle(.yellow).font(.system(size: 11))
            Text(title).foregroundStyle(.white).font(.system(size: 12, weight: .medium))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .frame(width: 116)
        .background(.white.opacity(0.08), in: Capsule())
    }
}

struct NotchShell: View {
    let model: NotchViewModel
    var body: some View {
        ZStack(alignment: .top) {
            Color.clear                                  // fill the (fixed-size) window canvas
            if model.phase == .expanded {
                VStack(spacing: 0) {
                    Color.clear.frame(height: model.topInset)     // reserve the notch/menubar strip
                    HStack(alignment: .center, spacing: 14) {
                        ForEach(model.widgets) { $0.content }      // player (left)
                        Rectangle().fill(.white.opacity(0.12)).frame(width: 1, height: 60)
                        QuickActionsPlaceholder()                  // shortcuts (right)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)
                    .padding(.top, 4)
                }
                .background(.black, in: NotchPanelShape())         // hardware-notch silhouette
                .transition(.scale(scale: 0.85, anchor: .top).combined(with: .opacity))
            } else {
                NotchPanelShape(topRadius: 6, bottomRadius: 12)
                    .fill(.black)
                    .frame(width: 180, height: 32)       // notch-sized collapsed shape
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // Bouncy: noticeable overshoot as the panel drops from the notch.
        .animation(.bouncy(duration: 0.45, extraBounce: 0.3), value: model.phase)
    }
}
