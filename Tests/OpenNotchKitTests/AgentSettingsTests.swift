import Testing
import Foundation
@testable import OpenNotchKit

private final class MemStorage: PluginStorage {
    var blob: Data?
    func data(forKey key: String) -> Data? { blob }
    func set(_ data: Data?, forKey key: String) { blob = data }
    func stringArray(forKey key: String) -> [String]? { nil }
    func set(_ array: [String]?, forKey key: String) {}
}

@Test func agentSettingsDefaultsWhenNothingOrGarbageStored() {
    let s = MemStorage()
    #expect(AgentSettings.load(from: s) == AgentSettings())
    #expect(AgentSettings().threshold == 3 && AgentSettings().windowMinutes == 10 && AgentSettings().alertsEnabled)
    s.blob = Data("not json".utf8)
    #expect(AgentSettings.load(from: s) == AgentSettings())
}

@Test func agentSettingsClampOnInitAndLoad() {
    #expect(AgentSettings(threshold: 0.1, windowMinutes: 1).threshold == 1.5)
    #expect(AgentSettings(threshold: 99, windowMinutes: 99).windowMinutes == 30)
    #expect(AgentSettings(threshold: 99, windowMinutes: 99).threshold == 10)
    #expect(AgentSettings(threshold: .nan).threshold == 3)
    let s = MemStorage()
    s.blob = Data(#"{"threshold":50,"windowMinutes":2,"alertsEnabled":false}"#.utf8)
    let l = AgentSettings.load(from: s)
    #expect(l.threshold == 10 && l.windowMinutes == 5 && !l.alertsEnabled)
}

@Test func agentSettingsRoundTrips() {
    let s = MemStorage()
    AgentSettings(threshold: 4.5, windowMinutes: 15, alertsEnabled: false).save(to: s)
    #expect(AgentSettings.load(from: s) == AgentSettings(threshold: 4.5, windowMinutes: 15, alertsEnabled: false))
}
