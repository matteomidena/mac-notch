import Testing
import CoreGraphics
@testable import OpenNotchKit

// Real geometries captured on-device (1512×982 built-in display, 33pt menubar).
private let display = CGRect(x: 0, y: 0, width: 1512, height: 982)

@Test func nativeFullscreenCoversNotch() {
    // True fullscreen covers the menubar strip: top at the display's true top.
    let fs = WindowSnapshot(frame: CGRect(x: 0, y: 0, width: 1512, height: 982), isOwnApp: false)
    #expect(FullscreenDetector.coversNotch([fs], mainDisplayFrame: display) == true)
}

@Test func maximizedFullBleedWindowDoesNotCover() {
    // The regression case: a maximized window with the Dock auto-hidden fills the
    // *visible* frame — top at the menubar (minY 33), bottom at the true screen
    // edge (maxY 982). The menubar stays visible, so it is NOT fullscreen. The old
    // 1px-bottom-gap heuristic misread this as fullscreen when the Dock was hidden.
    let maxed = WindowSnapshot(frame: CGRect(x: 0, y: 33, width: 1512, height: 949), isOwnApp: false)
    #expect(FullscreenDetector.coversNotch([maxed], mainDisplayFrame: display) == false)
}

@Test func maximizedWindowStoppingShortDoesNotCover() {
    let maxed = WindowSnapshot(frame: CGRect(x: 0, y: 33, width: 1512, height: 948), isOwnApp: false)
    #expect(FullscreenDetector.coversNotch([maxed], mainDisplayFrame: display) == false)
}

@Test func windowBelowMenubarNeverCovers() {
    // Any window that leaves the menubar visible (top ≈ menubar height) is a
    // regular/maximized window, never fullscreen — regardless of how far down it
    // reaches. This is the deliberate trade-off: in-window video fullscreen that
    // keeps the system menubar is no longer geometrically detected (tunable).
    let content = WindowSnapshot(frame: CGRect(x: 0, y: 33, width: 1512, height: 949), isOwnApp: false)
    #expect(FullscreenDetector.coversNotch([content], mainDisplayFrame: display) == false)
}

@Test func offscreenDecoyDoesNotCover() {
    let decoy = WindowSnapshot(frame: CGRect(x: 0, y: -73, width: 1512, height: 41), isOwnApp: false)
    #expect(FullscreenDetector.coversNotch([decoy], mainDisplayFrame: display) == false)
}

@Test func transientTopBarDoesNotCover() {
    // Covers the menubar but does not reach the bottom → not fullscreen.
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
        WindowSnapshot(frame: CGRect(x: 0, y: 33, width: 1512, height: 949), isOwnApp: false), // maximized full-bleed
        WindowSnapshot(frame: CGRect(x: 0, y: 0, width: 1512, height: 33), isOwnApp: false),    // top bar
        WindowSnapshot(frame: CGRect(x: 0, y: 0, width: 1512, height: 982), isOwnApp: false),   // native fullscreen
    ]
    #expect(FullscreenDetector.coversNotch(windows, mainDisplayFrame: display) == true)
}
