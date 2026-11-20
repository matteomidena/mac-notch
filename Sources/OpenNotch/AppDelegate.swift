import AppKit
import CoreText
import SwiftUI
import OpenNotchKit
import os

private let log = Logger(subsystem: "cafe.notch", category: "host")

private extension NSImage {
    func pngData(maxPixel: CGFloat = 32) -> Data? {
        let target = NSImage(size: NSSize(width: maxPixel, height: maxPixel))
        target.lockFocus()
        draw(in: NSRect(x: 0, y: 0, width: maxPixel, height: maxPixel))
        target.unlockFocus()
        guard let tiff = target.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}

/// Wires the real host (MediaRemote bridge) to the plugin runtime the
/// notch panel renders.
@MainActor
final class AppHost: PluginHost {
    let bridge: MediaRemoteBridge
    var nowPlaying: NowPlayingService { bridge }
    let agents: AgentUsageService

    init(bridge: MediaRemoteBridge, agents: AgentUsageService) {
        self.bridge = bridge
        self.agents = agents
    }

    func launchApp(bundleIdentifier: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            log.error("no app for bundle id \(bundleIdentifier)")
            return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    // Scanning + icon-encoding every installed app is expensive; the set rarely
    // changes within a session, so cache it. quickActions() pulls (fired on every
    // settings toggle via observation) hit the cache instead of re-scanning on the
    // main thread. ponytail: lifetime cache — a newly-installed app needs an app
    // restart to appear; add invalidation if that becomes a real need.
    private var cachedApps: [InstalledApp]?

    func installedApps() -> [InstalledApp] {
        if let cachedApps { return cachedApps }
        let fm = FileManager.default
        let dirs = ["/Applications", "/System/Applications",
                    (NSString(string: "~/Applications").expandingTildeInPath)]
        var seen = Set<String>()
        var apps: [InstalledApp] = []
        for dir in dirs {
            guard let entries = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for entry in entries where entry.hasSuffix(".app") {
                let path = "\(dir)/\(entry)"
                guard let bundle = Bundle(path: path),
                      let id = bundle.bundleIdentifier, !seen.contains(id) else { continue }
                seen.insert(id)
                let name = fm.displayName(atPath: path).replacingOccurrences(of: ".app", with: "")
                let data = NSWorkspace.shared.icon(forFile: path).pngData()
                apps.append(InstalledApp(bundleId: id, name: name, iconData: data))
            }
        }
        let sorted = apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        cachedApps = sorted
        return sorted
    }

    func invalidateAppCache() { cachedApps = nil }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var host: AppHost?
    private var runtime: PluginRuntime?
    private var displays: DisplayCoordinator?
    private var statusItem: NSStatusItem?
    private var blocklist: PluginBlocklist?
    private var pluginWatch: DispatchSourceFileSystemObject?
    private var loadedPluginIds = Set<String>()
    private let launcherStore = LauncherStore(
        storage: UserDefaultsPluginStorage(pluginId: "cafe.notch.launcher"))
    private let settings = SettingsWindowController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let paths = AdapterPaths.resolve(
            bundleResourceURL: Bundle.main.resourceURL,
            cwd: FileManager.default.currentDirectoryPath,
            fileExists: { FileManager.default.fileExists(atPath: $0) })
        CTFontManagerRegisterFontsForURL(URL(fileURLWithPath: paths.interFont) as CFURL, .process, nil)
        let bridge = MediaRemoteBridge(script: paths.script, framework: paths.framework)
        bridge.start()

        let agents = AgentUsage()
        agents.start()
        let host = AppHost(bridge: bridge, agents: agents)
        if launcherStore.bundleIds.isEmpty {
            launcherStore.add("com.apple.Safari")
            launcherStore.add("com.apple.iCal")     // Calendar
        }
        let runtime = PluginRuntime(host: host, plugins: [
            AgentsPlugin(host: host),
            MediaPlugin(host: host),
            AppLauncherPlugin(host: host, store: launcherStore),
        ])
        self.host = host
        self.runtime = runtime
        self.displays = DisplayCoordinator(runtime: runtime, nowPlaying: host.nowPlaying, agents: host.agents)

        let blocklist = PluginBlocklist(store: DefaultsMarkerStore())
        self.blocklist = blocklist
        let loader = PluginLoader()
        loadInstalledPlugins(host: host, runtime: runtime, loader: loader, blocklist: blocklist)
        self.pluginWatch = PluginsFolder.watch { [weak self] in
            guard let self, let host = self.host, let rt = self.runtime, let bl = self.blocklist else { return }
            self.loadInstalledPlugins(host: host, runtime: rt, loader: loader, blocklist: bl)
        }

        setUpStatusItem()
    }

    /// Load every `*.notchplugin` in the folder that isn't already loaded or
    /// blocklisted. Never unloads (dlopened code stays); an update needs a relaunch.
    private func loadInstalledPlugins(host: AppHost, runtime: PluginRuntime,
                                      loader: PluginLoader, blocklist: PluginBlocklist) {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: PluginsFolder.url, includingPropertiesForKeys: nil) else { return }
        for dir in entries where dir.pathExtension == "notchplugin" {
            guard let data = try? Data(contentsOf: dir.appendingPathComponent("manifest.json")),
                  let manifest = try? parsePluginManifest(data),
                  !loadedPluginIds.contains(manifest.id),
                  !blocklist.blocked.contains(manifest.id) else { continue }
            PluginsFolder.stripQuarantine(dir)
            blocklist.beginLoad(manifest.id)
            do {
                let plugin = try loader.load(pluginDirectory: dir, host: host)
                runtime.add([plugin])
                loadedPluginIds.insert(manifest.id)
                blocklist.endLoad(manifest.id)
                log.info("loaded plugin \(manifest.id)")
            } catch {
                blocklist.endLoad(manifest.id)   // a caught throw is a clean failure, not a crash
                log.error("failed to load \(manifest.id): \(String(describing: error))")
            }
        }
    }

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "OpenNotch")

        let menu = NSMenu()

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate), keyEquivalent: "q"))

        item.menu = menu
        statusItem = item
    }

    @objc private func openSettings() {
        host?.invalidateAppCache()
        guard let runtime else { return }
        settings.show(
            store: launcherStore,
            installedApps: host?.installedApps() ?? [],
            runtime: runtime,
            blockedIds: Array(blocklist?.blocked ?? []).sorted(),
            onUnblock: { [weak self] id in self?.blocklist?.unblock(id) },
            onUninstall: { [weak self] id in self?.uninstallPlugin(id) })
    }

    /// Disable now (dlopened code can't be unloaded) and delete the bundle so it
    /// won't reload on next launch.
    private func uninstallPlugin(_ id: String) {
        runtime?.setEnabled(id, false)
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: PluginsFolder.url, includingPropertiesForKeys: nil) else { return }
        for dir in entries where dir.pathExtension == "notchplugin" {
            guard let data = try? Data(contentsOf: dir.appendingPathComponent("manifest.json")),
                  let manifest = try? parsePluginManifest(data), manifest.id == id else { continue }
            try? fm.removeItem(at: dir)
            loadedPluginIds.remove(id)
        }
    }
}
