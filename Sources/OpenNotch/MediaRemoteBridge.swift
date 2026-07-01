import Foundation
import OpenNotchKit

@MainActor public final class MediaRemoteBridge: NowPlayingService {
    public private(set) var current: NowPlayingInfo?
    private let perl = "/usr/bin/perl"
    private let script: String       // vendor/.../mediaremote-adapter.pl
    private let framework: String    // vendor/.../MediaRemoteAdapter.framework
    private var stream: Process?

    public init(script: String, framework: String) {
        self.script = script; self.framework = framework
    }

    public func start() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: perl)
        // "--no-diff" so each streamed line is a complete snapshot (the adapter
        // diffs by default, emitting only changed keys — see spike/README.md).
        p.arguments = [script, framework, "stream", "--no-diff"]
        let pipe = Pipe(); p.standardOutput = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            guard let self, let s = String(data: h.availableData, encoding: .utf8) else { return }
            for line in s.split(separator: "\n") {
                if let info = NowPlayingParser.parse(line: String(line)) {
                    Task { @MainActor in self.current = info }
                }
            }
        }
        try? p.run(); stream = p
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
