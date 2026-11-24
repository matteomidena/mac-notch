import Testing
import SwiftUI
@testable import OpenNotchKit

@Test func codexCloudStaysInsideAndFillsItsRect() {
    let rect = CGRect(x: 10, y: 20, width: 100, height: 100)
    let b = CodexCloud().path(in: rect).boundingRect
    #expect(!CodexCloud().path(in: rect).isEmpty)
    #expect(rect.insetBy(dx: -0.01, dy: -0.01).contains(b))
    #expect(b.width >= rect.width * 0.9)
    #expect(b.height >= rect.height * 0.9)
}
