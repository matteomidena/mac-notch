import Foundation
import Observation

/// The user's chosen launcher apps, in order. `@Observable` so the settings UI
/// and the notch controller both react to changes; persisted to UserDefaults.
@Observable @MainActor public final class LauncherStore {
    public private(set) var bundleIds: [String]
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let key: String

    public init(defaults: UserDefaults = .standard, key: String = "launcher.bundleIds") {
        self.defaults = defaults
        self.key = key
        self.bundleIds = defaults.stringArray(forKey: key) ?? []
    }

    public func add(_ bundleId: String) {
        guard !bundleIds.contains(bundleId) else { return }
        bundleIds.append(bundleId)
        save()
    }

    public func remove(_ bundleId: String) {
        bundleIds.removeAll { $0 == bundleId }
        save()
    }

    public func contains(_ bundleId: String) -> Bool { bundleIds.contains(bundleId) }

    private func save() { defaults.set(bundleIds, forKey: key) }
}
