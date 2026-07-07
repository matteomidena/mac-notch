import Foundation

/// Persistence seam for blocklist markers (a flat list of plugin ids currently
/// "mid-load"). Backed by UserDefaults in the app; in-memory in tests.
public protocol MarkerStore: AnyObject {
    var markers: [String] { get set }
}

public final class InMemoryMarkerStore: MarkerStore {
    public var markers: [String]
    public init(markers: [String] = []) { self.markers = markers }
}

/// UserDefaults-backed marker store.
public final class DefaultsMarkerStore: MarkerStore {
    private let defaults: UserDefaults
    private let key: String
    public init(defaults: UserDefaults = .standard, key: String = "plugin.loadMarkers") {
        self.defaults = defaults
        self.key = key
    }
    public var markers: [String] {
        get { defaults.stringArray(forKey: key) ?? [] }
        set { defaults.set(newValue, forKey: key) }
    }
}

/// Crash-attribution: a marker is written *before* each dlopen/construct and
/// cleared on success. Anything already marked when a fresh instance is created
/// (i.e. it survived a host restart) is presumed to have crashed the host and
/// is `blocked` until the user unblocks it.
public final class PluginBlocklist {
    private let store: MarkerStore
    /// Markers present at construction — these crashed on a previous run.
    private let initialMarkers: Set<String>
    /// Ids the user unblocked this run.
    private var unblocked: Set<String> = []

    public init(store: MarkerStore) {
        self.store = store
        self.initialMarkers = Set(store.markers)
    }

    /// Crashed-last-run ids the user hasn't cleared this run.
    public var blocked: Set<String> { initialMarkers.subtracting(unblocked) }

    public func beginLoad(_ id: String) {
        guard !store.markers.contains(id) else { return }
        store.markers.append(id)
    }

    public func endLoad(_ id: String) {
        store.markers.removeAll { $0 == id }
    }

    public func unblock(_ id: String) {
        unblocked.insert(id)
        store.markers.removeAll { $0 == id }
    }
}
