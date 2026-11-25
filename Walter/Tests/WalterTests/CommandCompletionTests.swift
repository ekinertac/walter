// CommandCompletionTests.swift — offering and Tab-completing the command
// words ("repo", "qwok") in normal search (Launcher/CommandCompletion.swift).

import Testing
@testable import Walter

@Suite("CommandCompletion")
struct CommandCompletionTests {

    private func row(_ title: String, completion: String? = nil) -> SearchResult {
        SearchResult(title: title, subtitle: "", icon: nil, action: .copy(title), completion: completion)
    }

    // MARK: matching

    @Test func abbreviationMatchesCommand() {
        #expect(CommandCompletion.matching("qw", words: ["repo", "qwok"]) == ["qwok"])
        #expect(CommandCompletion.matching("rp", words: ["repo", "qwok"]) == ["repo"])
        #expect(CommandCompletion.matching("QWOK", words: ["repo", "qwok"]) == ["qwok"])
    }

    /// "o" is inside both words; offering them there would be noise.
    @Test func firstLetterMustMatch() {
        #expect(CommandCompletion.matching("o", words: ["repo", "qwok"]).isEmpty)
        #expect(CommandCompletion.matching("", words: ["repo", "qwok"]).isEmpty)
        #expect(CommandCompletion.matching("qwokx", words: ["repo", "qwok"]).isEmpty)
    }

    @Test func disabledAndDuplicateWordsAreDropped() {
        #expect(CommandCompletion.matching("r", words: ["", "repo", "Repo"]) == ["repo"])
    }

    // MARK: inserting

    @Test func commandNeverTakesFirstPlace() {
        let rows = CommandCompletion.inserting([row("repo")], into: [row("Reminders"), row("Reeder")])
        #expect(rows.map(\.title) == ["Reminders", "repo", "Reeder"])
    }

    @Test func commandIsFirstWhenNothingElseMatches() {
        #expect(CommandCompletion.inserting([row("qwok")], into: []).map(\.title) == ["qwok"])
    }

    // MARK: Tab

    @Test func tabPrefersSelectedRow() {
        let rows = [row("a", completion: "a "), row("b", completion: "b ")]
        #expect(CommandCompletion.tab(rows, selected: 1) == "b ")
    }

    @Test func tabFallsBackToOfferedCommand() {
        let rows = [row("Reminders"), row("repo", completion: "repo ")]
        #expect(CommandCompletion.tab(rows, selected: 0) == "repo ")
    }

    @Test func tabWithoutCompletionsDoesNothing() {
        #expect(CommandCompletion.tab([row("Reminders")], selected: 0) == nil)
        #expect(CommandCompletion.tab([], selected: 0) == nil)
    }
}
