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

    /// Reads `path` from `offset` in 4 MB chunks, handing each chunk's complete lines to `body`;
    /// nothing outlives a chunk. Returns the new offset.
    @discardableResult
    static func stream(_ path: String, from offset: UInt64 = 0, splitter: inout LineSplitter,
                       keep: (Data.SubSequence) -> Bool = { _ in true }, _ body: ([String]) -> Void) -> UInt64 {
        guard let fh = FileHandle(forReadingAtPath: path), (try? fh.seek(toOffset: offset)) != nil else { return offset }
        defer { try? fh.close() }
        var offset = offset
        // The pool must wrap the read: FileHandle hands back autoreleased buffers, and a
        // background task has no run loop to drain them (4 GB of chunks piled up without it).
        while autoreleasepool(invoking: {
            guard let chunk = try? fh.read(upToCount: 4 << 20), !chunk.isEmpty else { return false }
            offset += UInt64(chunk.count)
            body(splitter.feed(chunk, keep: keep))
            return true
        }) {}
        return offset
    }

    /// Limits from the newest Codex log that reports them, for a launch after Codex went quiet.
    static func newestCodexLimits() -> PlanLimits? {
        guard let walker = FileManager.default.enumerator(
            at: URL(fileURLWithPath: codex), includingPropertiesForKeys: [.contentModificationDateKey]) else { return nil }
        let dated = (walker.allObjects as? [URL] ?? []).filter { $0.pathExtension == "jsonl" }.map {
            ($0, (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
        }
        for (url, _) in dated.sorted(by: { $0.1 > $1.1 }).prefix(5) {
            var splitter = LineSplitter(), found: PlanLimits?
            stream(url.path, splitter: &splitter, keep: { $0.firstRange(of: needle.rateLimits) != nil }) { lines in
                if let l = lines.reversed().lazy.compactMap({ CodexLogParser.parse($0)?.limits }).first { found = l }
            }
            if let found { return found }
        }
        return nil
    }

    /// `*.jsonl` files under the existing roots modified at or after `since`.
    /// Byte patterns for skipping lines before decoding them.
    enum needle {
        static let usage = Data(#""usage""#.utf8)                  // Claude assistant line with tokens
        static let tokenCount = Data(#""token_count""#.utf8)       // Codex tokens (and rate limits)
        static let sessionMeta = Data(#""session_meta""#.utf8)     // Codex thread id: the session key
        static let rateLimits = Data(#""rate_limits""#.utf8)
    }

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
    private var seededCodexLimits: PlanLimits?  // until a live Codex log reports newer ones

    init(publish: @escaping @Sendable (AgentSnapshot) -> Void) { self.publish = publish }

    func start() {
        let live = AgentRoots.files(since: Date().addingTimeInterval(-AgentSession.waitingTTL))
        for path in live { read(path) }
        if sessions.latestLimits[.codex] == nil { seededCodexLimits = AgentRoots.newestCodexLimits() }
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
        publish(AgentSnapshot(live: sessions.live(at: Date()), codexLimits: sessions.latestLimits[.codex] ?? seededCodexLimits))
    }

    private func read(_ path: String) {
        guard let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size]) as? UInt64 else { return }
        var offset = offsets[path] ?? 0
        if size < offset {  // truncated or replaced
            offset = 0
            splitters[path] = LineSplitter()
        }
        guard size > offset else { return }
        var splitter = splitters[path] ?? LineSplitter()
        offsets[path] = AgentRoots.stream(path, from: offset, splitter: &splitter) {
            AgentRoots.ingest($0, path: path, into: sessions)
        }
        splitters[path] = splitter
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
/// The result is saved: a launch reuses it until it is a day old instead of re-reading gigabytes of logs.
enum AgentBaseline {
    private static let key = "agentBaseline", atKey = "agentBaselineAt"
    static let maxAge: TimeInterval = 86_400

    /// The saved rates and their age, if any.
    static func saved() -> (rates: [AgentKind: Double], age: TimeInterval)? {
        let d = UserDefaults.standard
        guard let raw = d.dictionary(forKey: key) as? [String: Double], let at = d.object(forKey: atKey) as? Date else { return nil }
        let rates = Dictionary(uniqueKeysWithValues: raw.compactMap { k, v in AgentKind(rawValue: k).map { ($0, v) } })
        return (rates, Date().timeIntervalSince(at))
    }

    static func compute() -> [AgentKind: Double] {
        let began = Date()
        let files = AgentRoots.files(since: began.addingTimeInterval(-30 * 86_400))
        let local = AgentSessions()
        for path in files {
            let codex = AgentRoots.agent(of: path) == .codex
            var splitter = LineSplitter()
            // Only token lines (and Codex's session key) move the baseline; the rest is skipped undecoded.
            AgentRoots.stream(path, splitter: &splitter, keep: { line in
                codex ? line.firstRange(of: AgentRoots.needle.tokenCount) != nil
                        || line.firstRange(of: AgentRoots.needle.sessionMeta) != nil
                      : line.firstRange(of: AgentRoots.needle.usage) != nil
            }) { AgentRoots.ingest($0, path: path, into: local) }
        }
        var averages: [AgentKind: [Double]] = [:]
        for s in local.sessions.values {
            averages[s.agent, default: []].append(
                Baseline.averageRate(weightedTotal: s.weightedTotal, activeMinutes: s.activeMinutes))
        }
        let normal = Dictionary(uniqueKeysWithValues: AgentKind.allCases.map {
            ($0, Baseline.normal(averages: averages[$0] ?? [], agent: $0)) })
        UserDefaults.standard.set(Dictionary(uniqueKeysWithValues: normal.map { ($0.key.rawValue, $0.value) }), forKey: key)
        UserDefaults.standard.set(Date(), forKey: atKey)
        log.info("baseline: \(files.count) files, \(local.sessions.count) sessions, \(Date().timeIntervalSince(began), format: .fixed(precision: 2)) s")
        return normal
    }
}
