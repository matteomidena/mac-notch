import Testing
import Foundation
@testable import OpenNotchKit

@Test func parsesValidManifest() throws {
    let json = """
    { "id": "weather", "name": "Weather", "version": "1.2.0",
      "author": "Acme", "apiVersion": "1.0.0", "bundleName": "Weather.bundle" }
    """.data(using: .utf8)!
    let m = try parsePluginManifest(json)
    #expect(m.id == "weather")
    #expect(m.name == "Weather")
    #expect(m.version == "1.2.0")
    #expect(m.author == "Acme")
    #expect(m.apiVersion == "1.0.0")
    #expect(m.bundleName == "Weather.bundle")
}

@Test func rejectsMissingRequiredField() {
    let json = #"{ "id": "weather", "name": "Weather" }"#.data(using: .utf8)!
    #expect(throws: ManifestError.self) { try parsePluginManifest(json) }
}

@Test func rejectsNonJSON() {
    let junk = Data([0x00, 0x01, 0x02])
    #expect(throws: ManifestError.self) { try parsePluginManifest(junk) }
}
