import Foundation

/// Locates the mediaremote-adapter script + framework: inside the app bundle's
/// Resources when packaged (Task 5's make-app.sh copies them there), else
/// relative to the working directory (dev mode: `swift run` from package root).
public enum AdapterPaths {
    public struct Resolved: Equatable {
        public let script: String
        public let framework: String
        public let interFont: String
    }

    public static func resolve(bundleResourceURL: URL?, cwd: String,
                               fileExists: (String) -> Bool) -> Resolved {
        // The font resolves independently of the adapter.
        var interFont = cwd + "/vendor/inter/InterVariable.ttf"
        if let bundled = bundleResourceURL?.appendingPathComponent("inter/InterVariable.ttf").path,
           fileExists(bundled) { interFont = bundled }
        if let base = bundleResourceURL?.appendingPathComponent("mediaremote-adapter") {
            let script = base.appendingPathComponent("bin/mediaremote-adapter.pl").path
            let framework = base.appendingPathComponent("build/MediaRemoteAdapter.framework").path
            if fileExists(script), fileExists(framework) {
                return Resolved(script: script, framework: framework, interFont: interFont)
            }
        }
        return Resolved(script: cwd + "/vendor/mediaremote-adapter/bin/mediaremote-adapter.pl",
                        framework: cwd + "/vendor/mediaremote-adapter/build/MediaRemoteAdapter.framework",
                        interFont: interFont)
    }
}
