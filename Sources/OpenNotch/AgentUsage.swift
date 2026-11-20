import Foundation
import Observation
import OpenNotchKit
import os

private let log = Logger(subsystem: "cafe.notch", category: "agents")

@MainActor @Observable
final class AgentUsage: AgentUsageService {
    private(set) var limits: [PlanLimits] = []
    private(set) var liveSessions: [AgentSession] = []
    private(set) var normalRate: [AgentKind: Double] = Baseline.defaultNormal
    private(set) var alert: RunawayAlert?
    var canControl: Bool { installer.isInstalled }
    let installer: HookInstaller

    var threshold = 3.0 { didSet { detector.config.threshold = threshold; evaluate() } }
    var window: TimeInterval = 600 { didSet { let w = window; Task { await watcher?.setRateWindow(w) } } }

    var alertsEnabled = true { didSet { evaluate() } }

    @ObservationIgnored private var detector = RunawayDetector()
    @ObservationIgnored private var watcher: AgentWatcher?
    @ObservationIgnored private var sessions: [AgentSession] = []
    @ObservationIgnored private var reevalTimer: Task<Void, Never>?
    @ObservationIgnored private var baselineTimer: Task<Void, Never>?
    @ObservationIgnored private var codexLimits: PlanLimits?
    @ObservationIgnored private var claudeLimits: PlanLimits?  // last good snapshot; kept across failures
    @ObservationIgnored private var fetchGate = ClaudeFetchGate()
    @ObservationIgnored private var fetching = false

    init(installer: HookInstaller = HookInstaller()) { self.installer = installer }

    func start() {
        let w = AgentWatcher { [weak self] snap in Task { @MainActor in self?.apply(snap) } }
        watcher = w
        Task { await w.start() }
        baselineTimer = Task { [weak self] in
            while !Task.isCancelled {
                let normal = await Task.detached(priority: .utility) { AgentBaseline.compute() }.value
                self?.normalRate = normal
                self?.evaluate()
                try? await Task.sleep(for: .seconds(24 * 3600))
            }
        }
    }

    func stop(sessionId: String) { send(.stop, sessionId) }
    func redirect(sessionId: String, text: String) { send(.redirect(text), sessionId) }
    func dismiss(sessionId: String) { acknowledge(sessionId) }
    /// Drops quiet sessions, then (if Connected and ≥ 60 s since the last attempt) refreshes Claude usage.
    func refreshLimits() {
        evaluate()
        fetchClaudeIfDue()
    }

    /// Settings "Connect": the consent gate. Nothing reads the Keychain before this.
    func connect() {
        UserDefaults.standard.set(true, forKey: ClaudeUsageClient.connectedKey)
        fetchGate = ClaudeFetchGate()
        fetchClaudeIfDue()
    }

    /// Settings "Disconnect": stops reading the Keychain and drops the Claude snapshot.
    func disconnect() {
        UserDefaults.standard.set(false, forKey: ClaudeUsageClient.connectedKey)
        claudeLimits = nil
        publishLimits()
    }

    /// Applies stored settings. Call after `start()`: a window set before it is lost (no watcher yet).
    func apply(_ s: AgentSettings) {
        threshold = s.threshold
        window = TimeInterval(s.windowMinutes * 60)
        alertsEnabled = s.alertsEnabled
    }

    private func fetchClaudeIfDue() {
        guard UserDefaults.standard.bool(forKey: ClaudeUsageClient.connectedKey), !fetching,
              fetchGate.allow(at: Date()) else { return }
        fetching = true
        Task { [weak self] in
            // Off the main actor: SecItemCopyMatching blocks while the prompt is up.
            let outcome = await Task.detached(priority: .utility) {
                await ClaudeUsageFlow.run(at: Date(), read: ClaudeUsageClient.readCredential,
                                          fetch: { await ClaudeUsageClient.fetch(token: $0) })
            }.value
            self?.finishFetch(outcome)
        }
    }

    private func finishFetch(_ outcome: ClaudeUsageOutcome) {
        fetching = false
        switch outcome {
        case .snapshot(let l): claudeLimits = l; publishLimits(); log.info("claude usage updated")
        case .none: log.info("claude usage: no new snapshot")
        case .denied:
            UserDefaults.standard.set(false, forKey: ClaudeUsageClient.connectedKey)
            claudeLimits = nil
            publishLimits()
            log.info("claude usage: keychain denied, disconnected")
        }
    }

    private func publishLimits() { limits = [claudeLimits, codexLimits].compactMap { $0 } }

    /// Claude only. The hook drops the in-flight tool call on stop, so nothing here promises it finishes.
    private func send(_ action: DirectiveAction, _ id: String) {
        if canControl, sessions.first(where: { $0.id == id })?.agent == .claude { installer.write(action, sessionId: id) }
        acknowledge(id)
    }

    private func acknowledge(_ id: String) {
        let now = Date()
        let rate = sessions.first { $0.id == id }?.burn.perMinute(at: now) ?? 0
        detector.acknowledge(sessionId: id, rate: rate, at: now)
        evaluate()
    }

    private func apply(_ snap: AgentSnapshot) {
        sessions = snap.live
        codexLimits = snap.codexLimits
        publishLimits()
        fetchClaudeIfDue()  // AgentSnapshot can't tell Claude events apart; the 60 s gate bounds the cost
        log.info("published \(snap.live.count) live sessions")
        evaluate()
    }

    /// In-memory only: no IO, safe to run every 60 s.
    private func evaluate() {
        let now = Date()
        let live = sessions.filter { $0.isLive(at: now) }
        var best: (RunawayAlert, Double)?
        var hot = false
        for s in live {
            let normal = normalRate[s.agent] ?? 0
            let rate = s.burn.perMinute(at: now)
            _ = detector.update(sessionId: s.id, rate: rate, weightedTotal: s.weightedTotal, normal: normal, at: now)
            hot = hot || (normal > 0 && rate >= threshold * normal && s.weightedTotal >= detector.config.floor)
            if detector.isFlagged(s.id), normal > 0, rate / normal > (best?.1 ?? 0) {
                best = (RunawayAlert(session: s, multiple: rate / normal, normal: normal), rate / normal)
            }
        }
        liveSessions = live
        alert = alertsEnabled ? best?.0 : nil
        // The detector measures its hold between update timestamps, and file events can be sparse.
        if alert != nil || hot {
            if reevalTimer == nil {
                reevalTimer = Task { [weak self] in
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(60))
                        self?.evaluate()
                    }
                }
            }
        } else {
            reevalTimer?.cancel()
            reevalTimer = nil
        }
    }
}
