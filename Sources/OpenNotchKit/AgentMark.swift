import SwiftUI

private struct AgentMarkImagesKey: EnvironmentKey {
    static let defaultValue: [AgentKind: Image] = [:]
}

public extension EnvironmentValues {
    /// Host-provided agent logo images (Claude's comes from the installed app). Empty by default.
    var agentMarkImages: [AgentKind: Image] {
        get { self[AgentMarkImagesKey.self] }
        set { self[AgentMarkImagesKey.self] = newValue }
    }
}

/// Scalloped cloud: 8 lobes (r 0.2) on a 0.3 ring around a 0.32 center disc, in the rect's square.
struct CodexCloud: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height)
        let c = CGPoint(x: rect.midX, y: rect.midY)
        var p = Path()
        func disc(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) {
            p.addEllipse(in: CGRect(x: x - r * s, y: y - r * s, width: 2 * r * s, height: 2 * r * s))
        }
        disc(c.x, c.y, 0.32)
        for i in 0..<8 {
            let a = Double(i) * .pi / 4
            disc(c.x + 0.3 * s * CGFloat(cos(a)), c.y + 0.3 * s * CGFloat(sin(a)), 0.2)
        }
        return p
    }
}

/// Small white agent logo. Claude: host image if any (else nothing); Codex: drawn.
struct AgentMark: View {
    let agent: AgentKind
    let size: CGFloat
    @Environment(\.agentMarkImages) private var images

    var body: some View {
        switch agent {
        case .claude:
            if let image = images[.claude] {
                image.renderingMode(.template).resizable().scaledToFit()
                    .foregroundStyle(Hex.ink).frame(width: size, height: size)
            }
        case .codex:
            CodexCloud().fill(Hex.ink).frame(width: size, height: size)
                .overlay { prompt.stroke(Hex.bg, style: StrokeStyle(lineWidth: 0.1 * size, lineCap: .round, lineJoin: .round)) }
        }
    }

    private var prompt: Path {
        Path { p in
            let s = size
            p.move(to: CGPoint(x: 0.24 * s, y: 0.36 * s))
            p.addLine(to: CGPoint(x: 0.36 * s, y: 0.50 * s))
            p.addLine(to: CGPoint(x: 0.24 * s, y: 0.64 * s))
            p.move(to: CGPoint(x: 0.51 * s, y: 0.64 * s))
            p.addLine(to: CGPoint(x: 0.75 * s, y: 0.64 * s))
        }
    }
}
