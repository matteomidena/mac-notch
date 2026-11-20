import CoreServices
import Foundation
import OpenNotchKit
import os

private let log = Logger(subsystem: "cafe.notch", category: "agents")

struct AgentSnapshot: Sendable {
    var live: [AgentSession]
    var codexLimits: PlanLimits?
}

enum AgentRoots {
    static let claude = NSString(string: "~/.claude/projects").expandingTildeInPath
    static let codex = NSString(string: "~/.codex/sessions").expandingTildeInPath
    static var existing: [String] {
        [claude, codex].filter { FileManager.default.fileExists(atPath: $0) }  // missing root: skipped, no retry
    }

    static func agent(of path: String) -> AgentKind { path.hasPrefix(codex) ? .codex : .claude }

    static func parse(_ line: String, agent: AgentKind) -> ParsedLogLine? {
        agent == .codex ? CodexLogParser.parse(line) : ClaudeLogParser.parse(line)
    }

    static func ingest(_ lines: [String], path: String, into sessions: AgentSessions) {
        let agent = agent(of: path)
        let ids = agent == .claude ? ClaudeLogParser.sessionIds(path: path) : nil
        for line in lines {
            if let parsed = parse(line, agent: agent) {
                sessions.ingest(parsed, agent: agent, fileKey: path, pathIds: ids)
            }
        }
    }

    /// `*.jsonl` files under the existing roots modified at or after `since`.
    static func files(since: Date) -> [String] {
        var out: [String] = []
        for root in existing {
            guard let walker = FileManager.default.enumerator(
                at: URL(fileURLWithPath: root), includingPropertiesForKeys: [.contentModificationDateKey]) else { continue }
            for case let url as URL in walker where url.pathExtension == "jsonl" {
                if let m = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                   m >= since { out.append(url.path) }
            }
        }
        return out
    }
}

/// Owns the live sessions, byte offsets and line splitters; all IO and parsing happen here, off the main actor.
actor AgentWatcher {
    private let sessions = AgentSessions()
    private var offsets: [String: UInt64] = [:]
    private var splitters: [String: LineSplitter] = [:]
    private let publish: @Sendable (AgentSnapshot) -> Void
    private var stream: FSEventStreamRef?

    init(publish: @escaping @Sendable (AgentSnapshot) -> Void) { self.publish = publish }

    func start() {
        let live = AgentRoots.files(since: Date().addingTimeInterval(-300))
        for path in live { read(path) }
        log.info("launch scan: \(live.count) live files, \(self.sessions.sessions.count) sessions")
        emit()
        startStream()
    }

    func setRateWindow(_ window: TimeInterval) {
        sessions.rateWindow = window
        emit()
    }

    private func handle(_ paths: [String]) {
        for path in paths where path.hasSuffix(".jsonl") { read(path) }  // unseen file: offset 0
        emit()
    }

    private func emit() {
        publish(AgentSnapshot(live: sessions.live(at: Date()), codexLimits: sessions.latestLimits[.codex]))
    }

    private func read(_ path: String) {
        guard let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size]) as? UInt64,
              let fh = FileHandle(forReadingAtPath: path) else { return }
        defer { try? fh.close() }
        var offset = offsets[path] ?? 0
        if size < offset {  // truncated or replaced
            offset = 0
            splitters[path] = LineSplitter()
        }
        guard size > offset, (try? fh.seek(toOffset: offset)) != nil else { return }
        var splitter = splitters[path] ?? LineSplitter()
        while let chunk = try? fh.read(upToCount: 4 << 20), !chunk.isEmpty {
            offset += UInt64(chunk.count)
            AgentRoots.ingest(splitter.feed(chunk), path: path, into: sessions)
        }
        splitters[path] = splitter
        offsets[path] = offset
    }

    // MARK: FSEvents

    private final class Box { let handler: @Sendable ([String]) -> Void; init(_ h: @escaping @Sendable ([String]) -> Void) { handler = h } }

    private func startStream() {
        let roots = AgentRoots.existing
        guard !roots.isEmpty else { return }
        let box = Box { [weak self] paths in Task { await self?.handle(paths) } }
        var ctx = FSEventStreamContext(version: 0, info: Unmanaged.passRetained(box).toOpaque(), retain: nil,
                                       release: { Unmanaged<Box>.fromOpaque($0!).release() }, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, count, paths, _, _ in
            let box = Unmanaged<Box>.fromOpaque(info!).takeUnretainedValue()
            let list = unsafeBitCast(paths, to: NSArray.self) as? [String] ?? []
            box.handler(Array(list.prefix(count)))
        }
        guard let s = FSEventStreamCreate(nil, callback, &ctx, roots as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.5,
                                          FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)) else {
            log.error("FSEventStreamCreate failed")
            return
        }
        FSEventStreamSetDispatchQueue(s, DispatchQueue(label: "cafe.notch.agents.fsevents", qos: .utility))
        FSEventStreamStart(s)
        stream = s
    }
}

/// Reads 30 days of logs into a throwaway `AgentSessions` and returns the per-agent normal rate. Never touches live state.
enum AgentBaseline {
    static func compute() -> [AgentKind: Double] {
        let began = Date()
        let files = AgentRoots.files(since: began.addingTimeInterval(-30 * 86_400))
        let local = AgentSessions()
        for path in files {
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe) else { continue }
            var splitter = LineSplitter()
            AgentRoots.ingest(splitter.feed(data), path: path, into: local)
        }
        var averages: [AgentKind: [Double]] = [:]
        for s in local.sessions.values {
            averages[s.agent, default: []].append(
                Baseline.averageRate(weightedTotal: s.weightedTotal, activeMinutes: s.activeMinutes))
        }
        let normal = Dictionary(uniqueKeysWithValues: AgentKind.allCases.map {
            ($0, Baseline.normal(averages: averages[$0] ?? [], agent: $0)) })
        log.info("baseline: \(files.count) files, \(local.sessions.count) sessions, \(Date().timeIntervalSince(began), format: .fixed(precision: 2)) s")
        return normal
    }
}
