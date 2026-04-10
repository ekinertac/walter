import Testing
@testable import Walter

@Suite("FuzzyMatch")
struct FuzzyMatchTests {

    @Test func exactMatch() {
        let r = fuzzyMatch(query: "Calculator", target: "Calculator")
        #expect(r.matched)
        #expect(r.score > 150)
    }

    @Test func acronymMatch() {
        let r = fuzzyMatch(query: "vsc", target: "Visual Studio Code")
        #expect(r.matched)
        #expect(r.score > 100)
    }

    @Test func substringMatch() {
        let r = fuzzyMatch(query: "calc", target: "Calculator")
        #expect(r.matched)
    }

    @Test func noMatch() {
        let r = fuzzyMatch(query: "xyz", target: "Calculator")
        #expect(!r.matched)
    }

    @Test func emptyQuery() {
        let r = fuzzyMatch(query: "", target: "anything")
        #expect(r.matched)
        #expect(r.score == 0)
    }

    @Test func boundaryScoresHigher() {
        let acronym = fuzzyMatch(query: "ff", target: "Firefox")
        let scattered = fuzzyMatch(query: "ff", target: "Staff")
        #expect(acronym.score > scattered.score)
    }

    @Test func caseInsensitive() {
        let r = fuzzyMatch(query: "FIRE", target: "Firefox")
        #expect(r.matched)
    }

    @Test func consecutiveRunBonus() {
        let consecutive = fuzzyMatch(query: "term", target: "Terminal")
        let scattered = fuzzyMatch(query: "trml", target: "Terminal")
        #expect(consecutive.score > scattered.score)
    }
}
