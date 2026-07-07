import Foundation

public enum PluginLoadError: Error, Equatable {
    case noManifest
    case manifest(String)
    case incompatible(String)
    case noExecutable
    case dlopenFailed(String)
    case noEntryPoint
}

public struct PluginLoader {
    /// dlopen seam (injectable for tests). Default: real dlopen.
    public var openExecutable: (String) -> UnsafeMutableRawPointer? = { path in
        dlopen(path, RTLD_NOW)
    }
    /// dlsym seam (injectable for tests). Default: real dlsym for the entry point.
    public var lookupEntry: (UnsafeMutableRawPointer) -> UnsafeMutableRawPointer? = { handle in
        dlsym(handle, pluginEntryPointName)
    }

    public init() {}

    public static func executableURL(pluginDirectory: URL, manifest: PluginManifest) -> URL {
        let bundle = pluginDirectory.appendingPathComponent(manifest.bundleName)
        let exeName = (manifest.bundleName as NSString).deletingPathExtension
        return bundle.appendingPathComponent("Contents/MacOS/\(exeName)")
    }

    @MainActor
    public func load(pluginDirectory: URL, host: PluginHost,
                     hostAPIVersion: String = OPENNOTCH_API_VERSION) throws -> NotchPlugin {
        let manifestURL = pluginDirectory.appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: manifestURL) else { throw PluginLoadError.noManifest }
        let manifest: PluginManifest
        do { manifest = try parsePluginManifest(data) }
        catch { throw PluginLoadError.manifest(String(describing: error)) }

        if case .incompatible(let reason) = apiCompatibility(host: hostAPIVersion, plugin: manifest.apiVersion) {
            throw PluginLoadError.incompatible(reason)
        }

        let exe = Self.executableURL(pluginDirectory: pluginDirectory, manifest: manifest)
        guard FileManager.default.fileExists(atPath: exe.path) else { throw PluginLoadError.noExecutable }
        guard let handle = openExecutable(exe.path) else {
            throw PluginLoadError.dlopenFailed(String(cString: dlerror()))
        }
        guard let sym = lookupEntry(handle) else { throw PluginLoadError.noEntryPoint }

        let create = unsafeBitCast(sym, to: PluginCreateFn.self)
        let boxPtr = create(hostPointer(host))
        return pluginFromBoxPointer(boxPtr)
    }
}
