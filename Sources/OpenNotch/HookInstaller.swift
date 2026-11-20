import Foundation
import Observation
import OpenNotchKit
import os

private let log = Logger(subsystem: "cafe.notch", category: "hook")

/// Installs the PreToolUse hook for Claude Code and writes Stop / Redirect directives for it.
/// Event-driven: `isInstalled` is read at init and after install/remove, never polled.
@MainActor @Observable
final class HookInstaller {
    private(set) var isInstalled = false
    private(set) var lastError: String?

    @ObservationIgnored private let home: URL
    private var support: URL { home.appending(path: "Library/Application Support/OpenNotch") }
    private var script: URL { support.appending(path: "hooks/pretooluse.sh") }
    private var directives: URL { support.appending(path: "directives") }
    private var settings: URL { home.appending(path: ".claude/settings.json") }
    /// One value for install, remove and isInstalled: the patch matches it by exact equality.
    private var command: String { "sh \"\(script.path)\"" }

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home
        refresh()
    }

    func install() {
        do {
            let fm = FileManager.default
            try fm.createDirectory(at: script.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(Directive.hookScript.utf8).write(to: script, options: .atomic)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
            let original = try readSettings()
            let patched = try ClaudeSettingsPatch.install(into: original, command: command)
            if let original { try backup(original) }
            try fm.createDirectory(at: settings.deletingLastPathComponent(), withIntermediateDirectories: true)
            try patched.write(to: settings, options: .atomic)
            lastError = nil
            log.info("hook installed")
        } catch { fail(error) }
        refresh()
    }

    func remove() {
        do {
            if let original = try readSettings() {
                let patched = try ClaudeSettingsPatch.remove(from: original, command: command)
                try patched.write(to: settings, options: .atomic)
            }
            lastError = nil
            log.info("hook removed")
        } catch { fail(error) }
        refresh()
    }

    /// Writes `directives/<id>.json` for the hook to consume. Nothing is written for an unsafe id.
    func write(_ action: DirectiveAction, sessionId: String) {
        guard Directive.isSafeSessionId(sessionId) else { return }
        do {
            try FileManager.default.createDirectory(at: directives, withIntermediateDirectories: true)
            try Directive.hookOutput(action).write(to: directives.appending(path: "\(sessionId).json"), options: .atomic)
            log.info("directive written")
        } catch { log.error("directive write failed") }
    }

    /// nil only when the file does not exist; an unreadable file throws so nothing gets overwritten.
    private func readSettings() throws -> Data? {
        FileManager.default.fileExists(atPath: settings.path) ? try Data(contentsOf: settings) : nil
    }

    private func refresh() {
        isInstalled = ClaudeSettingsPatch.isInstalled(in: try? Data(contentsOf: settings), command: command)
    }

    private func backup(_ original: Data) throws {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        try original.write(to: settings.appendingPathExtension("opennotch-backup-\(f.string(from: Date()))"), options: .atomic)
    }

    private func fail(_ error: Error) {
        switch error {
        case ClaudeSettingsPatch.PatchError.unexpectedShape: lastError = "settings.json has an unexpected hooks layout"
        case ClaudeSettingsPatch.PatchError.notAJSONObject:
            lastError = "settings.json is not valid JSON"
        default: lastError = "settings.json could not be read or written"
        }
        log.error("hook change failed")
    }
}
