import SwiftUI

private let fill = Hex.ink.opacity(0.024)

/// Closed-notch figure: the inverted badge while a runaway is flagged, else the tightest limit.
struct AgentsFigure: View {
    let service: AgentUsageService
    var body: some View {
        let now = Date()
        if let alert = service.alert {
            Text(multipleText(alert.multiple))
                .font(Hex.mono(12)).foregroundStyle(Hex.bg)
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(Hex.ink, in: RoundedRectangle(cornerRadius: 5.6))
        } else if let tight = tightestLimit(service.limits, at: now) {
            let pct = tight.window.percent(at: now)
            VStack(alignment: .trailing, spacing: 3) {
                Text("\(Int(pct.rounded()))%").font(Hex.mono(12)).foregroundStyle(Hex.ink)
                Capsule().fill(Hex.line(0.10)).frame(width: 28, height: 1.5)
                    .overlay(alignment: .leading) {
                        Capsule().fill(Hex.ink).frame(width: 28 * min(max(pct, 0), 100) / 100, height: 1.5)
                    }
            }
        }
    }
}

struct Tag: View {
    let agent: AgentKind
    var body: some View {
        Text(agent.rawValue).font(Hex.mono(10)).foregroundStyle(Hex.code)
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
        let now = Date()
        let claude = service.limits.first { $0.agent == .claude }
        let codex = service.limits.first { $0.agent == .codex }
        VStack(spacing: 8) {
            VStack(spacing: 0) {
                HStack { Text("Agents").font(Hex.text(14, weight: .semibold)).foregroundStyle(Hex.ink); Spacer() }
                    .padding(.horizontal, 12).padding(.vertical, 9)
                if let claude {
                    ForEach(claude.windows, id: \.label) { limitRow("Claude · \($0.label)", $0, now, age: limitAgeText(fetchedAt: claude.fetchedAt, now: now)) }
                } else {
                    row {
                        Text("Claude").font(Hex.text(12.5)).foregroundStyle(Hex.muted)
                        Spacer()
                        Text("—").font(Hex.mono(12)).foregroundStyle(Hex.ink)
                        Text("Connect in Settings").font(Hex.text(12)).foregroundStyle(Hex.muted)
                    }
                }
                if let codex {
                    ForEach(codex.windows, id: \.label) { limitRow("Codex · \($0.label)", $0, now) }
                    if let credits = codex.hasCredits {
                        row {
                            Text("Codex credits").font(Hex.text(12.5)).foregroundStyle(Hex.muted)
                            Spacer()
                            Text(credits ? "available" : "none").font(Hex.mono(12)).foregroundStyle(Hex.code)
                        }
                    }
                }
            }
            .panel()
            if !service.liveSessions.isEmpty {
                VStack(spacing: 0) {
                    ForEach(service.liveSessions) { sessionRow($0, now) }
                }
                .panel()
            }
        }
        .frame(maxWidth: 440)
    }

    private func row<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        HStack(spacing: 10, content: c)
            .padding(.horizontal, 12).padding(.vertical, 7).frame(minHeight: 32)
            .overlay(alignment: .top) { Hex.line(0.07).frame(height: 1) }
    }

    private func limitRow(_ title: String, _ w: LimitWindow, _ now: Date, age: String? = nil) -> some View {
        let pct = w.percent(at: now)
        let filled = Int((pct / 10).rounded())
        return row {
            Text(title).font(Hex.text(12.5)).foregroundStyle(Hex.muted)
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
        let rate = s.burn.perMinute(at: now)
        let flagged = service.alert?.session.id == s.id
        let normal = service.normalRate[s.agent]
        let times = normal.flatMap { $0 > 0 ? multipleText(rate / $0) : nil } ?? "—"
        return row {
            Tag(agent: s.agent)
            Text(s.project).font(Hex.text(13, weight: .medium)).foregroundStyle(Hex.ink).lineLimit(1)
            Spacer()
            Spark(values: s.burn.history(at: now))
            Text("\(compactCount(rate))/min").font(Hex.mono(12)).foregroundStyle(Hex.muted)
            Text(times).font(Hex.mono(12)).foregroundStyle(flagged ? Hex.bg : Hex.code)
                .padding(.horizontal, flagged ? 6 : 0).padding(.vertical, flagged ? 3 : 0)
                .background(flagged ? Hex.ink : .clear, in: RoundedRectangle(cornerRadius: 5.6))
            if flagged && s.agent == .claude && service.canControl {
                KeyCap(title: "Stop", hint: "esc", primary: true) { service.stop(sessionId: s.id) }
                    .scaleEffect(0.8).frame(width: 56, height: 28)
            }
        }
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
