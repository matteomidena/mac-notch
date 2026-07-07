import Foundation
import Observation

/// The user's chosen launcher apps, in order. `@Observable` so the settings UI
/// and the notch controller both react to changes; persisted to UserDefaults.
@Observable @MainActor public final class LauncherStore {
    public private(set) var bundleIds: [String]
    /// Hard cap on launcher pills — the expanded panel only has room for a few.
    public let maxCount: Int
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let key: String
    @ObservationIgnored private let storage: PluginStorage?

    public init(defaults: UserDefaults = .standard,
                key: String = "launcher.bundleIds",
                maxCount: Int = 3) {
        self.defaults = defaults
        self.key = key
        self.storage = nil
        self.maxCount = maxCount
        // Trim any previously-persisted overflow (e.g. cap lowered between versions).
        self.bundleIds = Array((defaults.stringArray(forKey: key) ?? []).prefix(maxCount))
    }

    /// Storage-backed init: persists `bundleIds` through the plugin's namespaced store.
    public init(storage: PluginStorage, maxCount: Int = 3) {
        self.storage = storage
        self.defaults = .standard
        self.key = "bundleIds"
        self.maxCount = maxCount
        self.bundleIds = Array((storage.stringArray(forKey: "bundleIds") ?? []).prefix(maxCount))
    }

    /// True when the cap is reached — the UI disables further additions.
    public var isFull: Bool { bundleIds.count >= maxCount }

    public func add(_ bundleId: String) {
        guard !bundleIds.contains(bundleId), !isFull else { return }
        bundleIds.append(bundleId)
        save()
    }

    public func remove(_ bundleId: String) {
        bundleIds.removeAll { $0 == bundleId }
        save()
    }

    public func contains(_ bundleId: String) -> Bool { bundleIds.contains(bundleId) }

    private func save() {
        if let storage { storage.set(bundleIds, forKey: "bundleIds") }
        else { defaults.set(bundleIds, forKey: key) }
    }
}
