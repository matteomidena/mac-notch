import Testing
@testable import OpenNotchKit

@Test func equalizerPausedIsStill() {
    for i in 0..<3 {
        #expect(EqualizerBars.level(i: i, t: 12.3, isPlaying: false, reduceMotion: false) == 0.22)
        #expect(EqualizerBars.level(i: i, t: 12.3, isPlaying: false, reduceMotion: true) == 0.22)
    }
}

@Test func equalizerPlayingStaysInRange() {
    for i in 0..<3 {
        for k in 0..<500 {
            let v = EqualizerBars.level(i: i, t: Double(k) * 0.05, isPlaying: true, reduceMotion: false)
            #expect(v >= 0.25 && v <= 1.0)
        }
    }
}

@Test func equalizerReduceMotionIsStatic() {
    let a = (0..<3).map { EqualizerBars.level(i: $0, t: 1, isPlaying: true, reduceMotion: true) }
    let b = (0..<3).map { EqualizerBars.level(i: $0, t: 9, isPlaying: true, reduceMotion: true) }
    #expect(a == [0.45, 0.75, 0.55] && b == a)
}

@Test func equalizerBarsAreOutOfPhase() {
    let v = (0..<3).map { EqualizerBars.level(i: $0, t: 2, isPlaying: true, reduceMotion: false) }
    #expect(Set(v).count == 3)
}
