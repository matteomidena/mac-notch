import Foundation
import os

private let log = Logger(subsystem: "cafe.notch", category: "plugins")

enum PluginsFolder {
    static var url: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("OpenNotch/Plugins", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Defensive de-quarantine on install (see the M3 spike doc): a Finder-launched
    /// host would otherwise refuse a downloaded, quarantined dylib on dlopen.
    static func stripQuarantine(_ dir: URL) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        p.arguments = ["-dr", "com.apple.quarantine", dir.path]
        try? p.run(); p.waitUntilExit()
    }

    /// Watch the folder; `onChange` fires on add/remove. Returns the source to retain.
    static func watch(_ onChange: @escaping () -> Void) -> DispatchSourceFileSystemObject? {
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { log.error("cannot watch plugins folder"); return nil }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        src.setEventHandler { onChange() }
        src.setCancelHandler { close(fd) }
        src.resume()
        return src
    }
}
