import SwiftUI
import AppKit
import ServiceManagement
import OpenNotchKit
import os

private let log = Logger(subsystem: "cafe.notch", category: "settings")

struct SettingsView: View {
    let agents: AgentUsage
    let store: LauncherStore
    let installedApps: [InstalledApp]
    let runtime: PluginRuntime
    let blockedIds: [String]
    let onUnblock: (String) -> Void
    let onUninstall: (String) -> Void
    var body: some View {
        TabView {
            GeneralTab().tabItem { Label("General", systemImage: "gearshape") }
            ShortcutsTab(store: store, apps: installedApps).tabItem { Label("Shortcuts", systemImage: "bolt") }
            AgentsTab(agents: agents).tabItem { Label("Agents", systemImage: "sparkles") }
            PluginsTab(runtime: runtime, initialBlocked: blockedIds,
                       onUnblock: onUnblock, onUninstall: onUninstall)
                .tabItem { Label("Plugins", systemImage: "puzzlepiece.extension") }
        }
        .frame(width: 460, height: 440)
    }
}

private struct PluginsTab: View {
    let runtime: PluginRuntime
    let initialBlocked: [String]
    let onUnblock: (String) -> Void
    let onUninstall: (String) -> Void
    @State private var blocked: [String] = []
    @State private var version = 0        // bump to force the list to re-read the runtime

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !blocked.isEmpty {
                GroupBox("Blocked (crashed on load)") {
                    ForEach(blocked, id: \.self) { id in
                        HStack {
                            Text(id).font(.callout)
                            Spacer()
                            Button("Unblock") { onUnblock(id); blocked.removeAll { $0 == id } }
                        }
                    }
                }
            }
            List(runtime.pluginSummaries, id: \.id) { p in
                HStack {
                    Toggle(p.name, isOn: Binding(
                        get: { runtime.isEnabled(p.id) },
                        set: { runtime.setEnabled(p.id, $0) }))
                    Spacer()
                    if p.hasSettings, let pane = runtime.settingsPane(for: p.id) {
                        SettingsDisclosure(pane: pane)
                    }
                    // Uninstall only for third-party (first-party ids start with "cafe.notch.").
                    if !p.id.hasPrefix("cafe.notch.") {
                        Button(role: .destructive) {
                            onUninstall(p.id); version += 1
                        } label: { Image(systemName: "trash") }
                        .buttonStyle(.borderless)
                    }
                }
            }
            .id(version)
        }
        .padding(20)
        .onAppear { blocked = initialBlocked }
    }
}

private struct SettingsDisclosure: View {
    let pane: AnyView
    @State private var open = false
    var body: some View {
        Button("Settings…") { open = true }
            .popover(isPresented: $open) { pane.padding() }
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
                        log.error("launch at login toggle failed: \(error)")
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
                }
        }
        .padding(20)
    }
}

private struct AgentsTab: View {
    let agents: AgentUsage
    @State private var settings = AgentSettings.load(from: Self.storage)
    @AppStorage(ClaudeUsageClient.connectedKey) private var claudeConnected = false
    private static let storage = UserDefaultsPluginStorage(pluginId: "cafe.notch.agents")

    var body: some View {
        Form {
            Section("Runaway alerts") {
                Toggle("Alerts", isOn: $settings.alertsEnabled)
                Stepper(value: $settings.threshold, in: AgentSettings.thresholdRange, step: 0.5) {
                    Text("Alert threshold: \(settings.threshold, format: .number.precision(.fractionLength(1)))× normal")
                }
                Stepper(value: $settings.windowMinutes, in: AgentSettings.windowRange) {
                    Text("Rate window: \(settings.windowMinutes) min")
                }
            }
            Section("Integrations") {
                LabeledContent("Claude plan usage") {
                    HStack {
                        Text(claudeConnected ? "Connected" : "Not connected").foregroundStyle(.secondary)
                        Button(claudeConnected ? "Disconnect" : "Connect") {
                            if claudeConnected { agents.disconnect() } else { agents.connect() }
                        }
                    }
                }
                LabeledContent("Claude hook") {
                    HStack {
                        Text(agents.installer.isInstalled ? "Installed" : "Not installed").foregroundStyle(.secondary)
                        Button(agents.installer.isInstalled ? "Remove" : "Install") {
                            if agents.installer.isInstalled { agents.installer.remove() } else { agents.installer.install() }
                        }
                    }
                }
                if let err = agents.installer.lastError {
                    Text(err).font(.caption).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: settings) { _, new in
            new.save(to: Self.storage)
            agents.apply(new)
        }
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
    func show(agents: AgentUsage, store: LauncherStore, installedApps: [InstalledApp],
              runtime: PluginRuntime, blockedIds: [String],
              onUnblock: @escaping (String) -> Void,
              onUninstall: @escaping (String) -> Void) {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 440),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = "OpenNotch Settings"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: SettingsView(
                agents: agents, store: store, installedApps: installedApps, runtime: runtime,
                blockedIds: blockedIds, onUnblock: onUnblock, onUninstall: onUninstall))
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
