import Foundation

enum PluginFixtureBuilder {
    /// Path to `swiftc`, or nil if unavailable (CI without a toolchain → skip).
    static var swiftcPath: String? {
        let candidates = ["/usr/bin/swiftc", "/usr/local/bin/swiftc"]
        if let found = candidates.first(where: { FileManager.default.fileExists(atPath: $0) }) {
            return found
        }
        // Fall back to `xcrun -f swiftc`.
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        p.arguments = ["-f", "swiftc"]
        let pipe = Pipe(); p.standardOutput = pipe
        try? p.run(); p.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (out?.isEmpty == false) ? out : nil
    }

    /// Build a `.notchplugin` whose entry point returns a pointer to a heap
    /// C string == `id`. Returns the plugin directory URL. Caller owns cleanup.
    static func build(id: String, apiVersion: String = "1.0.0",
                      into base: URL, swiftc: String) throws -> URL {
        let fm = FileManager.default
        let dir = base.appendingPathComponent("\(id).notchplugin")
        let bundle = dir.appendingPathComponent("\(id).bundle")
        let macos = bundle.appendingPathComponent("Contents/MacOS")
        try fm.createDirectory(at: macos, withIntermediateDirectories: true)

        let src = base.appendingPathComponent("\(id).swift")
        try """
        import Foundation
        @_cdecl("opennotch_plugin_create")
        public func opennotch_plugin_create(_ host: UnsafeMutableRawPointer) -> UnsafeMutableRawPointer {
            return UnsafeMutableRawPointer(mutating: strdup("\(id)"))
        }
        """.write(to: src, atomically: true, encoding: .utf8)

        let exe = macos.appendingPathComponent(id)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: swiftc)
        p.arguments = ["-emit-library", "-o", exe.path, src.path]
        try p.run(); p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            throw NSError(domain: "fixture", code: Int(p.terminationStatus))
        }

        let manifest = """
        { "id": "\(id)", "name": "\(id)", "version": "1.0.0",
          "author": "test", "apiVersion": "\(apiVersion)", "bundleName": "\(id).bundle" }
        """
        try manifest.write(to: dir.appendingPathComponent("manifest.json"),
                           atomically: true, encoding: .utf8)
        return dir
    }
}
