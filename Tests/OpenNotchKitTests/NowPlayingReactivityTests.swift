import Testing
import Observation
@testable import OpenNotchKit

// Guards the reactivity fix: SwiftUI re-renders the media widget only if reading
// `current` through the `any NowPlayingService` existential registers with the
// Observation framework. If NowPlayingService loses `Observable` or a conformer
// drops `@Observable`, this fails and the live widget silently stops updating.
final class Counter: @unchecked Sendable { var n = 0 }

@MainActor @Test func observingCurrentThroughProtocolExistentialFires() {
    let service: any NowPlayingService = FakeNowPlaying()
    let fired = Counter()
    withObservationTracking {
        _ = service.current            // tracked read through the existential
    } onChange: {
        fired.n += 1
    }
    (service as! FakeNowPlaying).current = NowPlayingInfo(title: "New Track")
    #expect(fired.n == 1)
}
