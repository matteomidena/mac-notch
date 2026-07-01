import Foundation
import OpenNotchKit

@MainActor public final class MediaRemoteBridge: NowPlayingService {
    public private(set) var current: NowPlayingInfo?
    private let perl = "/usr/bin/perl"
    private let script: String       // vendor/.../mediaremote-adapter.pl
    private let framework: String    // vendor/.../MediaRemoteAdapter.framework
    private var stream: Process?

    // Accumulates stream bytes across reads. Only ever touched inside the
    // readabilityHandler, which Foundation invokes serially on one background
    // queue — hence nonisolated(unsafe) is safe here.
    // ponytail: single-queue invariant; revisit if the read source ever changes.
    nonisolated(unsafe) private var lineBuffer = Data()

    public init(script: String, framework: String) {
        // dyld's dl_load_file (used by the perl adapter) requires an ABSOLUTE
        // path — a relative framework path silently fails to load. Resolve both
        // paths against the current directory up front.
        self.script = Self.absolutePath(script)
        self.framework = Self.absolutePath(framework)
    }

    private static func absolutePath(_ path: String) -> String {
        if (path as NSString).isAbsolutePath { return path }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(path).standardizedFileURL.path
    }

    public func start() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: perl)
        // "--no-diff" so each streamed payload is a complete snapshot (the adapter
        // diffs by default, emitting only changed keys — see spike/README.md).
        p.arguments = [script, framework, "stream", "--no-diff"]
        let pipe = Pipe(); p.standardOutput = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            guard let self else { return }
            let chunk = h.availableData
            guard !chunk.isEmpty else { return }
            // Artwork payloads are ~80KB and arrive split across 16KB reads, so a
            // single JSON line spans multiple chunks. Buffer and only parse
            // complete newline-terminated lines; keep the trailing partial line.
            self.lineBuffer.append(chunk)
            var latest: NowPlayingInfo?
            while let nl = self.lineBuffer.firstIndex(of: 0x0A) {
                let lineData = self.lineBuffer.subdata(in: self.lineBuffer.startIndex..<nl)
                self.lineBuffer.removeSubrange(self.lineBuffer.startIndex...nl)
                if let info = Self.parse(streamLine: lineData) { latest = info }
            }
            if let latest { Task { @MainActor in self.current = latest } }
        }
        try? p.run(); stream = p
    }

    // `stream` wraps fields in an envelope {"type":"data","payload":{…}}, whereas
    // `get` (what NowPlayingParser + the fixture were built against) puts fields at
    // top level. Unwrap the payload and feed the parser get-style JSON.
    nonisolated private static func parse(streamLine data: Data) -> NowPlayingInfo? {
        guard let env = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = env["payload"] as? [String: Any], !payload.isEmpty,
              let payloadData = try? JSONSerialization.data(withJSONObject: payload),
              let payloadLine = String(data: payloadData, encoding: .utf8)
        else { return nil }
        return NowPlayingParser.parse(line: payloadLine)
    }

    // Adapter transport commands are NUMERIC IDs (spike/README.md):
    // 0=play 1=pause 2=togglePlayPause 4=nextTrack 5=previousTrack.
    private func send(_ id: Int) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: perl)
        p.arguments = [script, framework, "send", String(id)]
        try? p.run()
    }

    public func play() { send(0) }
    public func pause() { send(1) }
    public func toggle() { send(2) }
    public func next() { send(4) }
    public func previous() { send(5) }
    // "seek" is a separate top-level command taking MICROSECONDS, not "send".
    public func seek(to time: TimeInterval) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: perl)
        p.arguments = [script, framework, "seek", String(Int(time * 1_000_000))]
        try? p.run()
    }
}
