import Testing
import Foundation
@testable import OpenNotchKit

private let sampleRate = 48_000.0
private let fftSize = 2048

private func sine(_ hz: Double) -> [Float] {
    (0..<fftSize).map { Float(sin(2 * Double.pi * hz * Double($0) / sampleRate)) }
}

/// Deterministic white noise (seeded LCG), full scale.
private func noise() -> [Float] {
    var state: UInt64 = 12345
    return (0..<fftSize).map { _ in
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Float(Int64(bitPattern: state) >> 40) / Float(1 << 23)
    }
}

private func run(_ samples: [Float], updates: Int = 10) -> [Double] {
    let analyzer = SpectrumAnalyzer(fftSize: fftSize)
    var bands = SpectrumBands(sampleRate: sampleRate, fftSize: fftSize)
    let mags = analyzer.magnitudes(samples)
    var levels: [Double] = []
    for _ in 0..<updates { levels = bands.update(magnitudes: mags) }
    return levels
}

@Test func lowSineLightsFirstBand() {
    let l = run(sine(100))
    #expect(l[0] > 0.5)
    #expect(l[0] > 3 * l[1])
    #expect(l[0] > 3 * l[2])
}

@Test func highSineLightsThirdBand() {
    let l = run(sine(5000))
    #expect(l[2] > l[0] && l[2] > l[1])
}

@Test func silenceDecaysSmoothly() {
    let analyzer = SpectrumAnalyzer(fftSize: fftSize)
    var bands = SpectrumBands(sampleRate: sampleRate, fftSize: fftSize)
    let loud = analyzer.magnitudes(noise())
    for _ in 0..<10 { _ = bands.update(magnitudes: loud) }
    let silent = analyzer.magnitudes([Float](repeating: 0, count: fftSize))
    var previous = bands.levels
    #expect(previous.allSatisfy { $0 > 0 })
    for _ in 0..<5 {
        let next = bands.update(magnitudes: silent)
        for i in next.indices {
            #expect(next[i] >= previous[i] * 0.92 - 1e-9)
            #expect(next[i] > 0)
        }
        previous = next
    }
}

@Test func levelsStayInRange() {
    let l = run(noise())
    #expect(l.allSatisfy { (0...1).contains($0) })
}

@Test func shortInputIsPadded() {
    let m = SpectrumAnalyzer(fftSize: fftSize).magnitudes(Array(sine(100).prefix(100)))
    #expect(m.count == fftSize / 2)
}
