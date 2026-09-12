import Foundation

public enum ManifestError: Error, Equatable {
    case malformed(String)
}

/// Parse a `.notchplugin` manifest.json into a `PluginManifest`.
/// All fields are required in the file; missing/extra/garbage → `.malformed`.
public func parsePluginManifest(_ data: Data) throws -> PluginManifest {
    do {
        return try JSONDecoder().decode(PluginManifest.self, from: data)
    } catch let e as DecodingError {
        throw ManifestError.malformed(String(describing: e))
    } catch {
        throw ManifestError.malformed(error.localizedDescription)
    }
}
