import AppKit
import ServiceManagement
import OpenNotchKit

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
        // ponytail: stub for now; will be wired to NSWorkspace.shared.open when needed
    }

    func installedApps() -> [InstalledApp] {
        // ponytail: stub for now; will be wired to AppKit enumeration when needed
        []
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var host: AppHost?
    private var runtime: PluginRuntime?
    private var notch: NotchController?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let bridge = MediaRemoteBridge(
            script: "vendor/mediaremote-adapter/bin/mediaremote-adapter.pl",
            framework: "vendor/mediaremote-adapter/build/MediaRemoteAdapter.framework")
        bridge.start()

        let host = AppHost(bridge: bridge)
        let runtime = PluginRuntime(host: host, plugins: [MediaPlugin(host: host)])
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
