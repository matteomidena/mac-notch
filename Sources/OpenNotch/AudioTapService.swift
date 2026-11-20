import AppKit
import CoreAudio
import Observation
import OpenNotchKit
import os

private let log = Logger(subsystem: "cafe.notch", category: "spectrum")

/// Mono sample ring shared between the IOProc (writer) and the analysis queue (reader).
private final class SampleRing: @unchecked Sendable {   // all state behind the lock
    private struct State {
        var samples = [Float](repeating: 0, count: 8192)
        var head = 0
        var sawSignal = false
    }
    static let window = 2048
    private let lock = OSAllocatedUnfairLock(initialState: State())

    /// IOProc side: no allocations (in-place writes into the preallocated array).
    func write(_ list: UnsafePointer<AudioBufferList>) {
        guard let buf = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: list)).first,
              let data = buf.mData?.assumingMemoryBound(to: Float.self) else { return }
        let ch = max(Int(buf.mNumberChannels), 1)
        let frames = Int(buf.mDataByteSize) / (MemoryLayout<Float>.size * ch)
        lock.withLockUnchecked { s in
            let n = s.samples.count
            for f in 0..<frames {
                var sum: Float = 0
                for c in 0..<ch { sum += data[f * ch + c] }
                let mono = sum / Float(ch)
                if mono != 0 { s.sawSignal = true }
                s.samples[s.head] = mono
                s.head = (s.head + 1) % n
            }
        }
    }

    func snapshot() -> (samples: [Float], sawSignal: Bool) {
        lock.withLock { s in
            let n = s.samples.count, start = s.head - Self.window + n
            return ((0..<Self.window).map { s.samples[(start + $0) % n] }, s.sawSignal)
        }
    }
}

/// FFT + band smoothing, plus the 30 Hz timer. Touched only on `queue`.
private final class Analysis: @unchecked Sendable {
    let queue = DispatchQueue(label: "cafe.notch.spectrum", qos: .userInitiated)
    let ring = SampleRing()
    private let analyzer = SpectrumAnalyzer(fftSize: 2048)
    private var bands: SpectrumBands
    private var timer: DispatchSourceTimer?
    private var started = DispatchTime.now()

    init(sampleRate: Double) {
        bands = SpectrumBands(sampleRate: sampleRate, fftSize: 2048)
    }

    func start(publish: @escaping @Sendable ([Double]) -> Void, silent: @escaping @Sendable () -> Void) {
        started = .now()   // silence clock starts now, after the (possibly prompt-blocked) tap setup
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: .milliseconds(33))
        t.setEventHandler { [self] in
            let (samples, sawSignal) = ring.snapshot()
            if !sawSignal {
                let elapsed = DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds
                if elapsed >= 3_000_000_000 { t.cancel(); silent() }   // permission denied looks like silence
                return
            }
            // ponytail: the 2-12 kHz band sums the most bins, so it reads ~16 dB hot on broadband
            // music; fix with a per-band offset if it looks wrong on the live check.
            publish(bands.update(magnitudes: analyzer.magnitudes(samples)))
        }
        timer = t
        t.resume()
    }

    func stop() { timer?.cancel(); timer = nil }
}

/// CoreAudio objects of one running tap. Only the setup queue creates them; main stores/destroys them.
private struct TapHandles: @unchecked Sendable {
    var tapID = AudioObjectID(kAudioObjectUnknown)
    var deviceID = AudioObjectID(kAudioObjectUnknown)
    var procID: AudioDeviceIOProcID?
    var analysis: Analysis?
}

private enum TapError: Error { case call(String, OSStatus) }

private func check(_ status: OSStatus, _ name: String) throws {
    if status != 0 {
        log.error("\(name, privacy: .public) status \(status, privacy: .public)")
        throw TapError.call(name, status)
    }
}

/// Safe on partial handles.
@available(macOS 14.2, *)
private func destroy(_ h: TapHandles) {
    if h.deviceID != kAudioObjectUnknown {
        if let p = h.procID {
            AudioDeviceStop(h.deviceID, p)
            AudioDeviceDestroyIOProcID(h.deviceID, p)
        }
        AudioHardwareDestroyAggregateDevice(h.deviceID)
    }
    if h.tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(h.tapID) }
}

/// Runs on the setup queue: AudioDeviceStart blocks until the owner answers the permission prompt.
@available(macOS 14.2, *)
private func buildTap(bundleId: String, ioQueue: DispatchQueue) throws -> TapHandles {
    guard var pid = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first?.processIdentifier
    else { throw TapError.call("no running app", 0) }
    var h = TapHandles()
    do {
        var processObject = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
                                              mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        try check(AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr,
                                             UInt32(MemoryLayout<pid_t>.size), &pid, &size, &processObject), "TranslatePIDToProcessObject")

        let desc = CATapDescription(stereoMixdownOfProcesses: [processObject])
        desc.isPrivate = true
        desc.muteBehavior = .unmuted
        try check(AudioHardwareCreateProcessTap(desc, &h.tapID), "AudioHardwareCreateProcessTap")

        let tapUID = desc.uuid.uuidString
        var format = AudioStreamBasicDescription()
        size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        addr.mSelector = kAudioTapPropertyFormat
        try check(AudioObjectGetPropertyData(h.tapID, &addr, 0, nil, &size, &format), "GetTapFormat")

        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "OpenNotch Spectrum",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: tapUID, kAudioSubTapDriftCompensationKey: true]],
        ]
        try check(AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &h.deviceID), "AudioHardwareCreateAggregateDevice")

        let analysis = Analysis(sampleRate: format.mSampleRate)
        let ring = analysis.ring
        h.analysis = analysis
        try check(AudioDeviceCreateIOProcIDWithBlock(&h.procID, h.deviceID, ioQueue) { _, input, _, _, _ in
            ring.write(input)
        }, "AudioDeviceCreateIOProcIDWithBlock")
        try check(AudioDeviceStart(h.deviceID, h.procID), "AudioDeviceStart")
        log.info("tap started, \(format.mSampleRate, privacy: .public) Hz, \(format.mChannelsPerFrame, privacy: .public) ch")
        return h
    } catch {
        destroy(h)
        throw error
    }
}

/// Live spectrum of the app that is playing, via a CoreAudio process tap (macOS 14.2+).
/// Anything that goes wrong sets `isAvailable = false` and the UI shows decorative bars.
@MainActor @Observable
final class AudioTap: SpectrumService {
    private(set) var levels: [Double] = [0, 0, 0]
    private(set) var isAvailable = false

    @ObservationIgnored private let nowPlaying: NowPlayingService
    /// Bundle id we last tried (even if it failed), so a failure is not retried until the
    /// source changes or playback stops and restarts.
    @ObservationIgnored private var attempted: String?
    @ObservationIgnored private var handles: TapHandles?
    /// Bumped on every start/teardown; async results from an older generation are discarded.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private let ioQueue = DispatchQueue(label: "cafe.notch.spectrum.io", qos: .userInteractive)
    @ObservationIgnored private let setupQueue = DispatchQueue(label: "cafe.notch.spectrum.setup")

    init(nowPlaying: NowPlayingService) { self.nowPlaying = nowPlaying }

    func start() {
        guard #available(macOS 14.2, *) else { return }
        withObservationTracking {
            _ = nowPlaying.current
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.sync()
                self?.start()   // re-arm
            }
        }
        sync()
    }

    private func sync() {
        guard #available(macOS 14.2, *) else { return }
        let info = nowPlaying.current
        let wanted = (info?.isPlaying ?? false) ? info?.sourceBundleId : nil
        guard let wanted else { attempted = nil; teardown(); return }
        guard wanted != attempted else { return }
        teardown()
        attempted = wanted
        let gen = generation
        let io = ioQueue
        setupQueue.async { [weak self] in
            let result = Result { try buildTap(bundleId: wanted, ioQueue: io) }
            Task { @MainActor in self?.setupFinished(result, gen) }
        }
    }

    @available(macOS 14.2, *)
    private func setupFinished(_ result: Result<TapHandles, Error>, _ gen: Int) {
        switch result {
        case .success(let h):
            guard gen == generation else { destroy(h); return }   // superseded while setting up
            handles = h
            h.analysis?.start(
                publish: { [weak self] l in Task { @MainActor in self?.publish(l, gen) } },
                silent: { [weak self] in Task { @MainActor in self?.silence(gen) } })
            isAvailable = true
        case .failure(let e):
            guard gen == generation else { return }
            fail("\(e)")
        }
    }

    private func publish(_ l: [Double], _ gen: Int) {
        if gen == generation { levels = l }
    }

    private func silence(_ gen: Int) {
        guard gen == generation else { return }
        fail("silence → fallback")
    }

    private func fail(_ why: String) {
        log.error("tap failed: \(why, privacy: .public)")
        teardown()
        isAvailable = false
    }

    /// Idempotent; also invalidates any setup still in flight.
    private func teardown() {
        generation += 1
        if let h = handles {
            h.analysis?.stop()
            if #available(macOS 14.2, *) { destroy(h) }
        }
        handles = nil
        levels = [0, 0, 0]   // bars settle
    }
}
