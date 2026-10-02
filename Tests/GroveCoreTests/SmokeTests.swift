import Testing
@testable import GroveCore

struct SmokeTests {
    @Test func versionIsSet() { #expect(!GroveCore.version.isEmpty) }
}
