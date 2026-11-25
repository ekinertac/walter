// CommandCompletion.swift — offers the command words ("repo", "qwok") in normal search
//
// Typing "qw" or "rp" offers the matching command as a row; Tab or Enter on
// it puts "qwok " / "repo " in the search field, which starts that mode.
// Pure functions only, so they are testable without the panel or the indexes.
//
// Called by: LauncherEngine.search (matching, inserting) and
// LauncherPanelController's Tab handler (tab).
// Related: GitHubIndex.swift, QwokIndex.swift (the modes themselves).
// Tests: Tests/WalterTests/CommandCompletionTests.swift.

import Foundation

enum CommandCompletion {
    /// Command words that `query` abbreviates: fuzzy match with the same
    /// first letter, because without that rule "o" would offer every command
    /// that contains an o. Empty (disabled) words are dropped, and so are
    /// duplicates, where the first one is also the mode that wins in search.
    static func matching(_ query: String, words: [String]) -> [String] {
        guard let first = query.lowercased().first else { return [] }
        var seen = Set<String>()
        return words.filter { word in
            word.lowercased().first == first
                && fuzzyMatch(query: query, target: word).matched
                && seen.insert(word.lowercased()).inserted
        }
    }

    /// Puts command rows after the best result, so a new command never takes
    /// Enter away from an app the user is used to launching.
    static func inserting(_ commands: [SearchResult], into results: [SearchResult]) -> [SearchResult] {
        Array(results.prefix(1)) + commands + Array(results.dropFirst())
    }

    /// Text that Tab puts in the field: the selected row's completion, else
    /// the first one offered, so "rp" + Tab works when an app is selected.
    static func tab(_ results: [SearchResult], selected: Int) -> String? {
        if results.indices.contains(selected), let own = results[selected].completion { return own }
        return results.lazy.compactMap(\.completion).first
    }
}
