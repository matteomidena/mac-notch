import SwiftUI

private let fill = Hex.ink.opacity(0.024)

/// Closed-notch figure. Priority: runaway badge, then how many sessions wait on you,
/// else the weekly Claude / Codex usage, alternating every 4 s.
struct AgentsFigure: View {
    let service: AgentUsageService
    var body: some View {
        let waiting = service.liveSessions.filter(\.needsYou).count
        if let alert = service.alert {
            Text(multipleText(alert.multiple))
                .font(Hex.mono(12)).foregroundStyle(Hex.bg)
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(Hex.ink, in: RoundedRectangle(cornerRadius: 5.6))
        } else if waiting > 0 {
            HStack(spacing: 5) {
                PulseDot(color: Hex.attention)
                Text("\(waiting)").font(Hex.mono(13).weight(.semibold)).foregroundStyle(Hex.attention)
            }
            .transition(.opacity)
        } else {
            let weekly = weeklyLimits(service.limits)
            if !weekly.isEmpty {
                TimelineView(.periodic(from: .now, by: 4)) { ctx in
                    let (agent, w) = weekly[Int(ctx.date.timeIntervalSince1970 / 4) % weekly.count]
                    let pct = w.percent(at: ctx.date)
                    HStack(spacing: 5) {
                        if service.liveSessions.contains(where: { $0.isLive(at: ctx.date) }) {
                            PulseDot(color: Hex.running, size: 5)
                        }
                        AgentMark(agent: agent, size: 12)
                        VStack(alignment: .trailing, spacing: 3) {
                            Text("\(Int(pct.rounded()))%").font(Hex.mono(12)).foregroundStyle(Hex.ink)
                            Capsule().fill(Hex.line(0.10)).frame(width: 24, height: 1.5)
                                .overlay(alignment: .leading) {
                                    Capsule().fill(Hex.ink).frame(width: 24 * min(max(pct, 0), 100) / 100, height: 1.5)
                                }
                        }
                    }
                    .id(agent)
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.35), value: agent)
                }
            }
        }
    }
}

/// Breathing status dot: amber while sessions wait on you, green while agents work.
struct PulseDot: View {
    let color: Color
    var size: CGFloat = 7
    @State private var on = false
    var body: some View {
        Circle().fill(color).frame(width: size, height: size)
            .shadow(color: color.opacity(on ? 0.9 : 0.2), radius: on ? 4 : 1)
            .opacity(on ? 1 : 0.45)
            .scaleEffect(on ? 1 : 0.8)
            .onAppear { withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { on = true } }
    }
}

/// The weekly window per agent, Claude first.
func weeklyLimits(_ all: [PlanLimits]) -> [(AgentKind, LimitWindow)] {
    AgentKind.allCases.compactMap { agent in
        all.first { $0.agent == agent }?.windows.first { $0.label == "Weekly" }.map { (agent, $0) }
    }
}

/// "5m 16s", "58s", "1h 4m"
func elapsedText(_ seconds: TimeInterval) -> String {
    let s = max(0, Int(seconds))
    if s < 60 { return "\(s)s" }
    if s < 3600 { return "\(s / 60)m \(s % 60)s" }
    return "\(s / 3600)h \(s % 3600 / 60)m"
}

/// Rounded app tile with the agent's mark, like a dock icon.
struct AgentTile: View {
    let agent: AgentKind
    var size: CGFloat = 28
    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.25)
            .fill(agent == .claude ? Color(red: 0xD9 / 255, green: 0x77 / 255, blue: 0x57 / 255)
                                   : Color(red: 0x3D / 255, green: 0x5A / 255, blue: 0xFE / 255))
            .frame(width: size, height: size)
            .overlay { AgentMark(agent: agent, size: size * 0.6) }
    }
}

struct Tag: View {
    let agent: AgentKind
    var body: some View {
        HStack(spacing: 4) {
            AgentMark(agent: agent, size: 9)
            Text(agent.rawValue).font(Hex.mono(10)).foregroundStyle(Hex.code)
        }
            .padding(.horizontal, 5).padding(.vertical, 3)
            .overlay(RoundedRectangle(cornerRadius: 5.6).stroke(Hex.line(0.14), lineWidth: 1))
    }
}

/// Hex's keycap: neutral gradient, black shadows. `primary` is the light one.
struct KeyCap: View {
    let title: String, hint: String, primary: Bool, action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(Hex.text(12, weight: .medium))
                .foregroundStyle(primary ? Hex.bg : Hex.ink)
                .frame(minWidth: 66, minHeight: 34, alignment: .bottomLeading)
                .padding(.horizontal, 10).padding(.bottom, 6)
                .overlay(alignment: .topTrailing) {
                    Text(hint).font(Hex.mono(10)).foregroundStyle(primary ? Color(white: 0.33) : Hex.muted)
                        .padding(.top, 6).padding(.trailing, 9)
                }
                .background(
                    RoundedRectangle(cornerRadius: 9).fill(LinearGradient(
                        colors: primary ? [Color(white: 0.97), Color(white: 0.86)]
                                        : [Color(white: 0.106), Color(white: 0.05)],
                        startPoint: .top, endPoint: .bottom)))
                .overlay(RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(Color.white.opacity(primary ? 0 : 0.14), lineWidth: 0.5))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color(white: 0.02), lineWidth: 1))
                .shadow(color: .black.opacity(0.75), radius: 7, y: 6)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Agents tab

struct AgentsTabView: View {
    let service: AgentUsageService

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let now = ctx.date
            let sessions = service.liveSessions
            let waiting = sessions.filter(\.needsYou).count
            VStack(spacing: 8) {
                // Limits stay put on top; the session list below grows and shrinks.
                limitsPanel(now)
                VStack(spacing: 0) {
                    HStack {
                        Text("Agents").font(Hex.text(14, weight: .semibold)).foregroundStyle(Hex.ink)
                        Spacer()
                        if waiting > 0 {
                            Text("\(waiting) NEEDS YOU").font(Hex.mono(10)).foregroundStyle(Hex.attention)
                        } else if !sessions.isEmpty {
                            Text("\(sessions.count) RUNNING").font(Hex.mono(10)).foregroundStyle(Hex.running)
                        }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    if sessions.isEmpty {
                        row { Text("No agents running").font(Hex.text(12.5)).foregroundStyle(Hex.muted); Spacer() }
                    } else {
                        ScrollView {
                            VStack(spacing: 0) { ForEach(sessions) { sessionRow($0, now) } }
                        }
                        .scrollBounceBehavior(.basedOnSize)
                        .scrollIndicators(.never)  // a legacy scroller gutter left a gap on the right
                    }
                }
                .panel()
            }
            .frame(maxWidth: 440)
        }
    }

    @ViewBuilder private func limitsPanel(_ now: Date) -> some View {
        let claude = service.limits.first { $0.agent == .claude }
        let codex = service.limits.first { $0.agent == .codex }
        VStack(spacing: 0) {
            if let claude {
                ForEach(claude.windows, id: \.label) { w in
                    // The 5h row also says when it resets.
                    let reset = w.label == "5h" ? resetText(w.resetsAt, now: now).map { " – resets in \($0)" } ?? "" : ""
                    limitRow(.claude, "Claude · \(w.label)\(reset)", w, now, age: limitAgeText(fetchedAt: claude.fetchedAt, now: now))
                }
            } else {
                row {
                    AgentTile(agent: .claude, size: 20)
                    Text("Claude").font(Hex.text(12.5)).foregroundStyle(Hex.muted)
                    Spacer()
                    Text("Connect in Settings").font(Hex.text(12)).foregroundStyle(Hex.muted)
                }
            }
            if let codex {
                ForEach(codex.windows, id: \.label) { limitRow(.codex, "Codex · \($0.label)", $0, now) }
            }
        }
        .panel()
    }

    private func row<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        HStack(spacing: 10, content: c)
            .padding(.horizontal, 12).padding(.vertical, 7).frame(minHeight: AgentsLayout.rowHeight)
            .overlay(alignment: .top) { Hex.line(0.07).frame(height: 1) }
    }

    private func limitRow(_ agent: AgentKind, _ title: String, _ w: LimitWindow, _ now: Date, age: String? = nil) -> some View {
        let pct = w.percent(at: now)
        let filled = Int((pct / 10).rounded())
        return row {
            HStack(spacing: 6) {
                AgentTile(agent: agent, size: 20)
                Text(title).font(Hex.text(12.5)).foregroundStyle(Hex.muted)
            }
            Spacer()
            if let age { Text(age).font(Hex.text(11)).foregroundStyle(Hex.muted) }
            HStack(spacing: 2) {
                ForEach(0..<10, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1).fill(i < filled ? Hex.ink : Hex.line(0.10))
                        .frame(width: 5, height: 8)
                }
            }
            Text("\(Int(pct.rounded()))%").font(Hex.mono(12)).foregroundStyle(Hex.ink)
                .frame(width: 36, alignment: .trailing)
        }
    }

    private func sessionRow(_ s: AgentSession, _ now: Date) -> some View {
        let flagged = service.alert?.session.id == s.id
        let tint = s.needsYou ? Hex.attention : Hex.running
        let status = s.needsYou ? "NEEDS YOU" : "RUNNING"
        let detail = s.detail ?? (s.needsYou ? "Your turn" : s.project)
        // Running: how long it has been going. Waiting: how long it has waited.
        let elapsed = now.timeIntervalSince(s.needsYou ? s.lastActivity : s.startedAt)
        return HStack(spacing: 10) {
            AgentTile(agent: s.agent)
            VStack(alignment: .leading, spacing: 3) {
                Text(s.displayTitle).font(Hex.text(13, weight: .medium)).foregroundStyle(Hex.ink).lineLimit(1)
                HStack(spacing: 5) {
                    PulseDot(color: tint, size: 5)
                    Text("\(status) · \(detail.uppercased())").font(Hex.mono(10)).foregroundStyle(tint).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if flagged {
                Text(multipleText(service.alert?.multiple ?? 0)).font(Hex.mono(11)).foregroundStyle(Hex.bg)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(Hex.ink, in: RoundedRectangle(cornerRadius: 5.6))
                if s.agent == .claude && service.canControl {
                    KeyCap(title: "Stop", hint: "esc", primary: true) { service.stop(sessionId: s.id) }
                        .scaleEffect(0.8).frame(width: 56, height: 28)
                }
            }
            Text(elapsedText(elapsed)).font(Hex.mono(11)).foregroundStyle(Hex.muted)
        }
        .padding(.horizontal, 10).padding(.vertical, 8).frame(minHeight: AgentsLayout.sessionRowHeight)
        .background(s.needsYou ? Hex.attention.opacity(0.07) : .clear)
        .overlay(alignment: .leading) {
            if s.needsYou { Hex.attention.frame(width: 2) }
        }
        .overlay(alignment: .top) { Hex.line(0.07).frame(height: 1) }
        .help(s.firstPrompt ?? s.project)
    }
}

/// 30-minute burn history; the newest third is drawn in full ink.
struct Spark: View {
    let values: [Double]
    var body: some View {
        let top = max(values.max() ?? 0, 1)
        HStack(alignment: .bottom, spacing: 1.5) {
            ForEach(Array(values.enumerated()), id: \.offset) { i, v in
                RoundedRectangle(cornerRadius: 1)
                    .fill(i >= values.count * 2 / 3 ? Hex.ink : Hex.ink.opacity(0.35))
                    .frame(width: 2, height: max(1, 14 * v / top))
            }
        }
        .frame(height: 14)
    }
}

private extension View {
    func panel() -> some View {
        self.background(fill, in: RoundedRectangle(cornerRadius: 12.8))
            .overlay(RoundedRectangle(cornerRadius: 12.8).stroke(Hex.line(0.10), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 12.8))
    }
}

// MARK: - Runaway strip

public struct RunawayStrip: View {
    let service: AgentUsageService
    let onFocusChange: (Bool) -> Void
    @State private var redirecting = false
    @State private var text = ""
    @FocusState private var focused: Bool

    public init(service: AgentUsageService, onFocusChange: @escaping (Bool) -> Void) {
        self.service = service; self.onFocusChange = onFocusChange
    }

    public var body: some View {
        Group {
            if let alert = service.alert { strip(alert) }
        }
        // Group stays in the hierarchy when the alert goes nil, so this still fires.
        .onChange(of: service.alert?.session.id) { if redirecting { close() } }
    }

    private func strip(_ alert: RunawayAlert) -> some View {
        let s = alert.session
        let now = Date()
        let actions = stripActions(for: s.agent, canControl: service.canControl)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Tag(agent: s.agent)
                Text("\(s.project) · \(multipleText(alert.multiple)) your normal")
                    .font(Hex.text(15, weight: .semibold)).foregroundStyle(Hex.ink).lineLimit(1)
                Spacer(minLength: 0)
                Button { service.dismiss(sessionId: s.id) } label: {
                    Text("×").font(Hex.mono(14)).foregroundStyle(Hex.muted)
                }.buttonStyle(.plain)
            }
            if let p = s.firstPrompt {
                Text("“\(p)”").font(Hex.text(13)).foregroundStyle(Hex.muted).lineLimit(1).padding(.top, 3)
            }
            let minutes = Int(now.timeIntervalSince(s.startedAt) / 60)
            Text("\(compactCount(s.burn.perMinute(at: now))) tok/min · \(compactCount(s.weightedTotal)) total · \(minutes) min")
                .font(Hex.mono(12)).foregroundStyle(Hex.muted).padding(.top, 2)
            if s.agent == .claude && !service.canControl {
                Text("Install the hook in Settings to stop sessions from here")
                    .font(Hex.text(12)).foregroundStyle(Hex.muted).padding(.top, 8)
            }
            HStack(spacing: 10) {
                Spacer()
                if actions.contains(.redirect) {
                    KeyCap(title: "Redirect", hint: "↵", primary: false) { open() }
                }
                if actions.contains(.stop) {
                    KeyCap(title: "Stop", hint: "esc", primary: true) { service.stop(sessionId: s.id) }
                }
            }
            .padding(.top, actions.count > 1 ? 10 : 0)
            if redirecting {
                HStack(spacing: 8) {
                    TextField("Tell it what to do instead", text: $text)
                        .textFieldStyle(.plain).font(Hex.text(13)).foregroundStyle(Hex.ink)
                        .focused($focused)
                        .onAppear { focused = true }
                        .onSubmit { send(s.id) }
                        .onKeyPress(.escape) { close(); return .handled }
                    Text("send ↵").font(Hex.mono(12)).foregroundStyle(Hex.muted)
                }
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(fill, in: RoundedRectangle(cornerRadius: 8.8))
                .overlay(RoundedRectangle(cornerRadius: 8.8).stroke(Hex.line(0.14), lineWidth: 1))
                .padding(.top, 10)
            }
        }
        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 14)
        .frame(maxWidth: 360)
    }

    private func open() {
        redirecting = true; onFocusChange(true)
    }

    private func close() {
        redirecting = false; text = ""; onFocusChange(false)
    }

    private func send(_ id: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { service.redirect(sessionId: id, text: t) }
        close()
    }
}

// MARK: - Open panel strip, beside the camera

/// Left of the camera: live token burn across all sessions.
struct BurnRateLabel: View {
    let service: AgentUsageService
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let rate = totalBurn(service.liveSessions, at: ctx.date)
            HStack(spacing: 5) {
                if rate > 0 { PulseDot(color: Hex.running, size: 5) }
                Text("\(compactCount(rate)) tok/min").font(Hex.mono(11))
                    .foregroundStyle(rate > 0 ? Hex.ink : Hex.muted)
            }
        }
    }
}
