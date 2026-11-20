import SwiftUI
import Observation
import OpenNotchKit

/// The hardware-notch silhouette: full-width top edge that flares into the screen
/// with a small *concave* (inverse) radius at the top corners, and convex rounded
/// bottom corners — so the panel reads as an extension of the physical notch.
struct NotchPanelShape: Shape {
    var topRadius: CGFloat = 10      // inverse (concave) flare
    var bottomRadius: CGFloat = 22   // convex round
    var animatableData: CGFloat { get { bottomRadius } set { bottomRadius = newValue } }
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
    var tabs: [PluginTab] = []
    var selectedTab: String?
    /// Set by the controller: re-size the footprint after a tab click (height follows the tab).
    @ObservationIgnored var onSelectTab: (() -> Void)?
    var topInset: CGFloat = 32          // menubar/notch height reserved at the top
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

    var tabItems: [TabItem] {
        TabBar.items(providerTabs: tabs.map { TabItem(id: $0.id, title: $0.title, systemImage: $0.systemImage) },
                     hasWidgets: !widgets.isEmpty, hasQuickActions: !quickActions.isEmpty)
    }
    func select(_ id: String) { selectedTab = id; onSelectTab?() }

    /// Panel size per tab: Agents is tall, everything else is the short panel.
    static let panelWidth: CGFloat = 440
    static let pillHeight: CGFloat = 36
    static let pillGap: CGFloat = 8
    static func panelHeight(forTab id: String?) -> CGFloat { id == "agents" ? 300 : 150 }
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

/// The Launcher tab: one pill per plugin-contributed QuickAction, as a grid.
private struct QuickActionsGrid: View {
    let actions: [QuickAction]
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)
    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(actions) { action in
                Button(action: action.action) {
                    HStack(spacing: 8) {
                        icon(for: action)
                        Text(action.title)
                            .foregroundStyle(.white).font(Hex.text(12, weight: .medium))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 9)
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

/// Floating tab pill under the panel: the active tab shows icon + title, the rest icon only.
private struct TabPill: View {
    let model: NotchViewModel
    var body: some View {
        HStack(spacing: 4) {
            ForEach(model.tabItems, id: \.id) { item in
                let active = item.id == model.selectedTab
                Button { model.select(item.id) } label: {
                    HStack(spacing: 6) {
                        Image(systemName: item.systemImage).font(.system(size: 13))
                        if active { Text(item.title).font(Hex.text(12, weight: .medium)).lineLimit(1) }
                    }
                    .foregroundStyle(active ? Hex.ink : Hex.muted)
                    .padding(.horizontal, 12).frame(height: NotchViewModel.pillHeight - 8)
                    .background(active ? Hex.line(0.14) : .clear, in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .frame(height: NotchViewModel.pillHeight)
        .background(.black, in: Capsule())
        .overlay(Capsule().strokeBorder(Hex.line(0.10), lineWidth: 1))
    }
}

struct NotchShell: View {
    let model: NotchViewModel
    var body: some View {
        ZStack(alignment: .top) {
            NotchPanelShape(topRadius: 10, bottomRadius: model.isOpen ? 20 : 12)
                .fill(.black)
                .frame(width: model.footprint.width, height: model.footprint.height)
            content
                .frame(width: model.footprint.width, height: model.footprint.height,
                       alignment: .top)
                .clipped()
            if model.isOpen {
                TabPill(model: model)
                    .padding(.top, model.footprint.height + NotchViewModel.pillGap)
                    .transition(.notchContent)
            }
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
                tabContent
                    .padding(.horizontal, 16).padding(.bottom, 10).padding(.top, 4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .transition(.notchContent)
        } else if model.showAmbient {
            ambientBar
        }
    }

    @ViewBuilder private var tabContent: some View {
        switch model.selectedTab {
        case "widgets": ScrollView { widgetGrid }
        case "launcher": ScrollView { QuickActionsGrid(actions: model.quickActions) }
        default:
            if let tab = model.tabs.first(where: { $0.id == model.selectedTab }) { tab.content }
        }
    }

    // Widgets arranged in a grid. A single wide widget is one full row.
    @ViewBuilder private var widgetGrid: some View {
        let laid = WidgetLayout.arrange(model.widgets.map { ($0.id, $0.size) }, columns: 4)
        let byRow = Dictionary(grouping: laid, by: \.row).sorted { $0.key < $1.key }
        VStack(spacing: 8) {
            ForEach(byRow, id: \.key) { _, cells in
                HStack(spacing: 8) {
                    ForEach(cells, id: \.id) { cell in
                        if let w = model.widgets.first(where: { $0.id == cell.id }) {
                            w.content
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private var ambientBar: some View {
        HStack(spacing: 0) {
            model.compactLeading
            Spacer(minLength: model.notchGap)
            model.compactTrailing
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.opacity)
    }
}
