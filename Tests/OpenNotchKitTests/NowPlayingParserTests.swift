import Testing
import Foundation
@testable import OpenNotchKit

@Test func parsesPlayingTrack() {
    let line = #"{"title":"Song","artist":"Artist","album":"Album","elapsedTime":12.5,"duration":200,"playing":true}"#
    let info = NowPlayingParser.parse(line: line)
    #expect(info?.title == "Song")
    #expect(info?.artist == "Artist")
    #expect(info?.isPlaying == true)
    #expect(info?.elapsed == 12.5)
    #expect(info?.duration == 200)
}

@Test func playingFalseMeansPaused() {
    // Real adapter output: paused lines carry "playing":false and omit playbackRate entirely.
    let line = #"{"title":"S","playing":false}"#
    #expect(NowPlayingParser.parse(line: line)?.isPlaying == false)
}

@Test func malformedOrBlankReturnsNil() {
    #expect(NowPlayingParser.parse(line: "") == nil)
    #expect(NowPlayingParser.parse(line: "not json") == nil)
}

@Test func parsesFixtureLines() throws {
    guard let fixtureURL = Bundle.module.url(forResource: "Fixtures/nowplaying-sample", withExtension: "jsonl") else {
        #expect(Bool(false), "Fixture file not found")
        return
    }
    let content = try String(contentsOf: fixtureURL, encoding: .utf8)
    let lines = content.split(separator: "\n", omittingEmptySubsequences: true)

    var foundTitle = false
    for line in lines {
        if let info = NowPlayingParser.parse(line: String(line)) {
            if let title = info.title, !title.isEmpty {
                foundTitle = true
                break
            }
        }
    }

    #expect(foundTitle, "At least one parsed line should have a non-nil title")
}

@Test func parsesSourceBundleId() {
    let line = #"{"title":"Song","playing":true,"bundleIdentifier":"com.apple.Music"}"#
    let info = NowPlayingParser.parse(line: line)
    #expect(info?.sourceBundleId == "com.apple.Music")
}

@Test func missingBundleIdentifierIsNil() {
    let info = NowPlayingParser.parse(line: #"{"title":"Song","playing":true}"#)
    #expect(info?.sourceBundleId == nil)
}
