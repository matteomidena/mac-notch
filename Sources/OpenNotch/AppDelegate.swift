import AppKit
import ServiceManagement
import SwiftUI
import OpenNotchKit

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

    init(bridge: MediaRemoteBridge) {
        self.bridge = bridge
    }

    func launchApp(bundleIdentifier: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            NSLog("OpenNotch: no app for bundle id \(bundleIdentifier)")
            return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    func installedApps() -> [InstalledApp] {
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
        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var host: AppHost?
    private var runtime: PluginRuntime?
    private var notch: NotchController?
    private var statusItem: NSStatusItem?
    private let launcherStore = LauncherStore()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let bridge = MediaRemoteBridge(
            script: "vendor/mediaremote-adapter/bin/mediaremote-adapter.pl",
            framework: "vendor/mediaremote-adapter/build/MediaRemoteAdapter.framework")
        bridge.start()

        let host = AppHost(bridge: bridge)
        if launcherStore.bundleIds.isEmpty {
            launcherStore.add("com.apple.Safari")
            launcherStore.add("com.apple.iCal")     // Calendar
        }
        let runtime = PluginRuntime(host: host, plugins: [
            MediaPlugin(host: host),
            AppLauncherPlugin(host: host, store: launcherStore),
        ])
        let notch = NotchController(runtime: runtime, nowPlaying: host.nowPlaying)
        notch.show()

        self.host = host
        self.runtime = runtime
        self.notch = notch

        setUpStatusItem()
    }

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "OpenNotch")

        let menu = NSMenu()

        let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(loginItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate), keyEquivalent: "q"))

        item.menu = menu
        statusItem = item
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("OpenNotch: failed to toggle launch at login: \(error)")
        }
        sender.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }
}
