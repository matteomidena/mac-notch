import Testing
import Foundation

/// The keystone contract: plugin-visible kit files import only SwiftUI, Foundation
/// or Observation, never AppKit or anything else.
@Test func pluginFacingKitFilesImportOnlyAllowedModules() throws {
    let kit = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // OpenNotchKitTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // package root
        .appendingPathComponent("Sources/OpenNotchKit")
    let files = ["PluginAPI.swift", "PluginBox.swift", "EventQueue.swift", "WidgetLayout.swift",
                 "HostServices.swift", "TabBar.swift", "AgentModel.swift", "AgentSessions.swift",
                 "HexStyle.swift", "AgentsPlugin.swift", "AgentsViews.swift", "AgentsLayout.swift", "AgentSettings.swift", "AgentMark.swift"]
    for f in files {
        let src = try String(contentsOf: kit.appendingPathComponent(f), encoding: .utf8)
        let imports = src.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("import ") || $0.hasPrefix("@testable import ") || $0.hasPrefix("@_exported import ") }
            .map { String($0.split(separator: " ").last ?? "") }
        for module in imports {
            #expect(["SwiftUI", "Foundation", "Observation"].contains(module), "\(f) must not import \(module)")
        }
    }
}
