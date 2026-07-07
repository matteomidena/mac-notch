/// The plugin API version this host implements. Bump the MAJOR on any
/// source-breaking change to the plugin-facing API; loader refuses mismatched majors.
public let OPENNOTCH_API_VERSION = "1.0.0"

public enum APICompatibility: Equatable {
    case compatible
    case incompatible(reason: String)
}

private func major(_ v: String) -> Int? {
    let parts = v.split(separator: ".")
    guard parts.count == 3, let m = Int(parts[0]),
          Int(parts[1]) != nil, Int(parts[2]) != nil else { return nil }
    return m
}

public func apiCompatibility(host: String, plugin: String) -> APICompatibility {
    guard let hostMajor = major(host) else {
        return .incompatible(reason: "host API version '\(host)' is not semver")
    }
    guard let pluginMajor = major(plugin) else {
        return .incompatible(reason: "plugin API version '\(plugin)' is not semver")
    }
    guard hostMajor == pluginMajor else {
        return .incompatible(reason: "plugin needs API v\(pluginMajor).x, host is v\(hostMajor).x")
    }
    return .compatible
}
