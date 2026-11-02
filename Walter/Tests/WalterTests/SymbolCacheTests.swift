import Testing
@testable import Walter

private final class FixtureSymbol {}

@Suite("In-memory built-in symbol cache (mock loader)")
struct SymbolCacheTests {
    @Test func repeatedPairLoadsOnceAndReusesIdentity() {
        var loads = 0
        let cache = SymbolCache<FixtureSymbol> { _, _ in loads += 1; return FixtureSymbol() }
        let first = cache.image(name: "gear", description: "Settings")
        let second = cache.image(name: "gear", description: "Settings")
        #expect(first === second)
        #expect(first != nil)
        #expect(loads == 1)
    }

    @Test func missingSymbolIsCachedToo() {
        var loads = 0
        let cache = SymbolCache<FixtureSymbol> { _, _ in loads += 1; return nil }
        #expect(cache.image(name: "missing", description: "Fixture") == nil)
        #expect(cache.image(name: "missing", description: "Fixture") == nil)
        #expect(loads == 1)
    }

    @Test func symbolDescriptionsAndCacheLifetimesStayIndependent() {
        var loads = 0
        let cache = SymbolCache<FixtureSymbol> { _, _ in loads += 1; return FixtureSymbol() }
        let first = cache.image(name: "gear", description: "One")
        let otherDescription = cache.image(name: "gear", description: "Two")
        let otherName = cache.image(name: "link", description: "One")
        #expect(first !== otherDescription)
        #expect(first !== otherName)
        let separate = SymbolCache<FixtureSymbol> { _, _ in loads += 1; return FixtureSymbol() }
        #expect(separate.image(name: "gear", description: "One") !== first)
        #expect(loads == 4)
    }
}
