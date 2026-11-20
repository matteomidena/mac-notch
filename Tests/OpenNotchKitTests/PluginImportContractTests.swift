import Testing
import Foundation

/// The keystone contract: plugin-visible kit files import only SwiftUI/Foundation,
/// never AppKit — so a plugin author never needs AppKit.
@Test func pluginFacingKitFilesDoNotImportAppKit() throws {
    let kit = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // OpenNotchKitTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // package root
        .appendingPathComponent("Sources/OpenNotchKit")
    let files = ["PluginAPI.swift", "PluginBox.swift", "EventQueue.swift", "WidgetLayout.swift",
                 "HostServices.swift", "TabBar.swift", "AgentModel.swift", "AgentSessions.swift",
                 "HexStyle.swift", "AgentsPlugin.swift", "AgentsViews.swift", "AgentsLayout.swift", "AgentSettings.swift"]
    for f in files {
        let src = try String(contentsOf: kit.appendingPathComponent(f), encoding: .utf8)
        #expect(!src.contains("import AppKit"), "\(f) must not import AppKit")
    }
}
