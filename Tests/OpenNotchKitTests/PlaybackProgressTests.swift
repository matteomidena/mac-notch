import Testing
import Foundation
@testable import OpenNotchKit

private let t0 = Date(timeIntervalSinceReferenceDate: 1000)

@Test func extrapolatesWhilePlaying() {
    let info = NowPlayingInfo(isPlaying: true, elapsed: 30, duration: 200, timestamp: t0)
    #expect(PlaybackProgress.position(info: info, at: t0.addingTimeInterval(5)) == 35)
}

@Test func frozenWhilePaused() {
    let info = NowPlayingInfo(isPlaying: false, elapsed: 30, duration: 200, timestamp: t0)
    #expect(PlaybackProgress.position(info: info, at: t0.addingTimeInterval(60)) == 30)
}

@Test func clampsToDuration() {
    let info = NowPlayingInfo(isPlaying: true, elapsed: 195, duration: 200, timestamp: t0)
    #expect(PlaybackProgress.position(info: info, at: t0.addingTimeInterval(60)) == 200)
}

@Test func nilElapsedGivesNil() {
    let info = NowPlayingInfo(isPlaying: true, timestamp: t0)
    #expect(PlaybackProgress.position(info: info, at: t0) == nil)
}

@Test func missingTimestampReturnsRawElapsed() {
    let info = NowPlayingInfo(isPlaying: true, elapsed: 30, duration: 200)
    #expect(PlaybackProgress.position(info: info, at: t0) == 30)
}
