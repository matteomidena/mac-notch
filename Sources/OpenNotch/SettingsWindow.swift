import SwiftUI
import AppKit
import ServiceManagement
import OpenNotchKit

struct SettingsView: View {
    let store: LauncherStore
    let installedApps: [InstalledApp]
    var body: some View {
        TabView {
            GeneralTab().tabItem { Label("General", systemImage: "gearshape") }
            ShortcutsTab(store: store, apps: installedApps).tabItem { Label("Shortcuts", systemImage: "bolt") }
        }
        .frame(width: 460, height: 440)
    }
}

private struct GeneralTab: View {
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    var body: some View {
        Form {
            Toggle("Launch at Login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, on in
                    do {
                        if on { try SMAppService.mainApp.register() }
                        else { try SMAppService.mainApp.unregister() }
                    } catch {
                        NSLog("OpenNotch: launch at login toggle failed: \(error)")
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
                }
        }
        .padding(20)
    }
}

private struct ShortcutsTab: View {
    let store: LauncherStore
    let apps: [InstalledApp]
    @State private var query = ""
    private var filtered: [InstalledApp] {
        query.isEmpty ? apps : apps.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                TextField("Search apps", text: $query).textFieldStyle(.roundedBorder)
                Text("\(store.bundleIds.count)/\(store.maxCount)")
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            List(filtered) { app in
                Toggle(isOn: Binding(
                    get: { store.contains(app.bundleId) },
                    set: { $0 ? store.add(app.bundleId) : store.remove(app.bundleId) }
                )) {
                    HStack(spacing: 8) {
                        if let d = app.iconData, let img = NSImage(data: d) {
                            Image(nsImage: img).resizable().frame(width: 20, height: 20)
                        }
                        Text(app.name)
                    }
                }
                // At the cap, only let the user turn things off.
                .disabled(!store.contains(app.bundleId) && store.isFull)
            }
        }
        .padding(20)
    }
}

@MainActor final class SettingsWindowController {
    private var window: NSWindow?
    func show(store: LauncherStore, installedApps: [InstalledApp]) {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 440),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = "OpenNotch Settings"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: SettingsView(store: store, installedApps: installedApps))
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
