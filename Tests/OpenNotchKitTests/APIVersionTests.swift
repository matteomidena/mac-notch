import Testing
@testable import OpenNotchKit

@Test func sameMajorIsCompatible() {
    #expect(apiCompatibility(host: "1.0.0", plugin: "1.0.0") == .compatible)
    #expect(apiCompatibility(host: "1.4.2", plugin: "1.0.9") == .compatible)
}

@Test func differentMajorIsIncompatible() {
    if case .incompatible = apiCompatibility(host: "1.0.0", plugin: "2.0.0") {} else {
        Issue.record("expected incompatible across majors")
    }
}

@Test func unparsableVersionIsIncompatible() {
    if case .incompatible = apiCompatibility(host: "1.0.0", plugin: "banana") {} else {
        Issue.record("expected incompatible for unparsable version")
    }
}

@Test func hostConstantIsSemver() {
    #expect(apiCompatibility(host: OPENNOTCH_API_VERSION, plugin: OPENNOTCH_API_VERSION) == .compatible)
}

@Test func oneOneHostAcceptsOneZeroPlugin() {
    #expect(apiCompatibility(host: "1.1.0", plugin: "1.0.0") == .compatible)
    #expect(OPENNOTCH_API_VERSION == "1.1.0")
}
