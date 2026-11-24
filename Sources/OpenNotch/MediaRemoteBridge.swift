import Foundation
import Observation
import OpenNotchKit
import os

private let log = Logger(subsystem: "cafe.notch", category: "media")

@Observable @MainActor public final class MediaRemoteBridge: NowPlayingService {
    // Only `current` is observed (drives the SwiftUI widget). Everything else is
    // implementation detail and excluded from observation.
    public private(set) var current: NowPlayingInfo?
    public private(set) var isAvailable = true
    @ObservationIgnored private var restartPolicy = RestartPolicy()
    @ObservationIgnored private var stopping = false
    @ObservationIgnored private var lastRaw: NowPlayingInfo?   // nil: nothing playing
    @ObservationIgnored private let perl = "/usr/bin/perl"
    @ObservationIgnored private let script: String       // vendor/.../mediaremote-adapter.pl
    @ObservationIgnored private let framework: String    // vendor/.../MediaRemoteAdapter.framework
    @ObservationIgnored private var stream: Process?

    // Accumulates stream bytes across reads. Only ever touched inside the
    // readabilityHandler, which Foundation invokes serially on one background
    // queue — hence nonisolated(unsafe) is safe here.
    // ponytail: single-queue invariant; revisit if the read source ever changes.
    @ObservationIgnored nonisolated(unsafe) private var lineBuffer = Data()

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
        guard stream == nil else { return }
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
            var latest: NowPlayingInfo??   // .some(nil): the player went away
            while let nl = self.lineBuffer.firstIndex(of: 0x0A) {
                let lineData = self.lineBuffer.subdata(in: self.lineBuffer.startIndex..<nl)
                self.lineBuffer.removeSubrange(self.lineBuffer.startIndex...nl)
                if let event = NowPlayingParser.parse(streamLine: lineData) { latest = event }
            }
            if let latest {
                Task { @MainActor in
                    self.restartPolicy.recordSuccess()
                    self.isAvailable = true
                    // De-dup: the --no-diff stream re-sends full snapshots
                    // (incl. ~80KB artwork); identical payloads must not
                    // re-trigger every observer.
                    guard latest != self.lastRaw else { return }
                    self.lastRaw = latest
                    self.current = latest.map { var s = $0; s.timestamp = Date(); return s }
                }
            }
        }
        p.terminationHandler = { [weak self] _ in
            Task { @MainActor in self?.streamEnded() }
        }
        try? p.run(); stream = p
    }

    private func streamEnded() {
        stream = nil
        guard !stopping else { return }
        switch restartPolicy.recordFailure(at: Date()) {
        case .restart(let delay):
            log.notice("adapter stream died; restarting in \(delay)s")
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.start()
            }
        case .giveUp:
            log.error("adapter stream keeps dying; media marked unavailable")
            current = nil
            isAvailable = false
        }
    }

    public func stop() {
        stopping = true
        stream?.terminate()
        stream = nil
    }

    deinit {
        stream?.terminate()
    }

    private func runAdapter(_ args: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: perl)
        p.arguments = [script, framework] + args
        do {
            try p.run()
        } catch {
            log.error("adapter command failed: \(error)")
        }
    }

    // Adapter transport commands are NUMERIC IDs (spike/README.md):
    // 0=play 1=pause 2=togglePlayPause 4=nextTrack 5=previousTrack.
    private func send(_ id: Int) { runAdapter(["send", String(id)]) }

    public func play() { send(0) }
    public func pause() { send(1) }
    public func toggle() { send(2) }
    public func next() { send(4) }
    public func previous() { send(5) }
    public func toggleShuffle() { send(6) }
    // "seek" is a separate top-level command taking MICROSECONDS, not "send".
    public func seek(to time: TimeInterval) {
        runAdapter(["seek", String(Int(time * 1_000_000))])
    }
}
