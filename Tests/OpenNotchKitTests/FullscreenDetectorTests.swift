import Testing
import CoreGraphics
@testable import OpenNotchKit

// Real geometries captured on-device (1512×982 built-in display).
private let display = CGRect(x: 0, y: 0, width: 1512, height: 982)

@Test func nativeFullscreenCoversNotch() {
    let fs = WindowSnapshot(frame: CGRect(x: 0, y: 0, width: 1512, height: 982), isOwnApp: false)
    #expect(FullscreenDetector.coversNotch([fs], mainDisplayFrame: display) == true)
}

@Test func chromiumVideoFullscreenCoversNotch() {
    // Content window reaches the true display bottom (maxY 982).
    let content = WindowSnapshot(frame: CGRect(x: 0, y: 33, width: 1512, height: 949), isOwnApp: false)
    #expect(FullscreenDetector.coversNotch([content], mainDisplayFrame: display) == true)
}

@Test func maximizedWindowDoesNotCover() {
    // The critical case: fills below the menubar but stops 1pt short (maxY 981).
    let maxed = WindowSnapshot(frame: CGRect(x: 0, y: 33, width: 1512, height: 948), isOwnApp: false)
    #expect(FullscreenDetector.coversNotch([maxed], mainDisplayFrame: display) == false)
}

@Test func offscreenDecoyDoesNotCover() {
    // Chromium shoves its normal window off the top during fullscreen.
    let decoy = WindowSnapshot(frame: CGRect(x: 0, y: -73, width: 1512, height: 41), isOwnApp: false)
    #expect(FullscreenDetector.coversNotch([decoy], mainDisplayFrame: display) == false)
}

@Test func transientTopBarDoesNotCover() {
    let bar = WindowSnapshot(frame: CGRect(x: 0, y: 0, width: 1512, height: 33), isOwnApp: false)
    #expect(FullscreenDetector.coversNotch([bar], mainDisplayFrame: display) == false)
}

@Test func ownFullscreenWindowNeverCovers() {
    let mine = WindowSnapshot(frame: display, isOwnApp: true)
    #expect(FullscreenDetector.coversNotch([mine], mainDisplayFrame: display) == false)
}

@Test func noWindowsMeansNotCovered() {
    #expect(FullscreenDetector.coversNotch([], mainDisplayFrame: display) == false)
}

@Test func picksFullscreenOutOfAMixedWindowList() {
    let windows = [
        WindowSnapshot(frame: CGRect(x: 0, y: 33, width: 1512, height: 948), isOwnApp: false), // maximized
        WindowSnapshot(frame: CGRect(x: 0, y: 0, width: 1512, height: 33), isOwnApp: false),    // top bar
        WindowSnapshot(frame: CGRect(x: 0, y: 33, width: 1512, height: 949), isOwnApp: false),  // fullscreen content
    ]
    #expect(FullscreenDetector.coversNotch(windows, mainDisplayFrame: display) == true)
}
