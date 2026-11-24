import Foundation
import Testing
@testable import OpenNotchKit

@Test func resetTextFormatsHoursAndMinutes() {
    let now = Date(timeIntervalSince1970: 0)
    #expect(resetText(now.addingTimeInterval(2 * 3600 + 14 * 60 + 30), now: now) == "2h 14m")
    #expect(resetText(now.addingTimeInterval(14 * 60), now: now) == "14m")
    #expect(resetText(now.addingTimeInterval(20), now: now) == "1m")
    #expect(resetText(now.addingTimeInterval(-1), now: now) == nil)
    #expect(resetText(nil, now: now) == nil)
}
