import Foundation

/// Per-plugin key-value store. Keys are namespaced by plugin id so plugins
/// can't read or clobber each other's data.
public protocol PluginStorage: AnyObject {
    func data(forKey key: String) -> Data?
    func set(_ data: Data?, forKey key: String)
    func stringArray(forKey key: String) -> [String]?
    func set(_ array: [String]?, forKey key: String)
}

public final class UserDefaultsPluginStorage: PluginStorage {
    private let defaults: UserDefaults
    private let prefix: String
    public init(pluginId: String, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.prefix = "plugin.\(pluginId)."
    }
    private func k(_ key: String) -> String { prefix + key }
    public func data(forKey key: String) -> Data? { defaults.data(forKey: k(key)) }
    public func set(_ data: Data?, forKey key: String) { defaults.set(data, forKey: k(key)) }
    public func stringArray(forKey key: String) -> [String]? { defaults.stringArray(forKey: k(key)) }
    public func set(_ array: [String]?, forKey key: String) { defaults.set(array, forKey: k(key)) }
}
