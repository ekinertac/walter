// GitHubIndexTests.swift — query parsing and owner/repo ranking for GitHub
// repo search (Launcher/GitHubIndex.swift). Fixture data only; the gh
// process and disk cache are not exercised here.

import Testing
@testable import Walter

@Suite("GitHubIndex")
struct GitHubIndexTests {

    let data = GitHubData(
        login: "ekinertac",
        orgs: ["Humbl-Solutions-OU", "curiousgamesdev"],
        repos: ["ekinertac/qwok", "ekinertac/walter",
                "Humbl-Solutions-OU/humbl-streaming", "Humbl-Solutions-OU/humbl.ai",
                "Humbl-Solutions-OU/infrastructure",
                "hum/tools", "curiousgamesdev/rgs"]
    )

    // MARK: parse

    @Test func ownerPhaseWhileTypingFirstWord() {
        #expect(GitHubQuery.parse("hum") == .owner("hum"))
        #expect(GitHubQuery.parse("") == .owner(""))
    }

    @Test func trailingSpaceAfterOwnerStartsRepoPhase() {
        #expect(GitHubQuery.parse("Humbl-Solutions-OU ") == .repo(owner: "Humbl-Solutions-OU", word: ""))
        #expect(GitHubQuery.parse("hum str") == .repo(owner: "hum", word: "str"))
    }

    // MARK: owners

    @Test func ownerPriorityMeThenOrgsThenCollaborators() {
        #expect(GitHubRanking.owners(data) == ["ekinertac", "curiousgamesdev", "Humbl-Solutions-OU", "hum"])
    }

    @Test func orgBeatsCollaboratorEvenWithLowerScore() {
        // Collaborator "hum" is an exact match and scores higher; the org must still come first.
        #expect(fuzzyMatch(query: "hum", target: "hum").score > fuzzyMatch(query: "hum", target: "Humbl-Solutions-OU").score)
        #expect(GitHubRanking.matchingOwners(data, word: "hum") == ["Humbl-Solutions-OU", "hum"])
    }

    @Test func emptyOwnerWordListsAllInPriorityOrder() {
        #expect(GitHubRanking.matchingOwners(data, word: "").first == "ekinertac")
    }

    @Test func resolveOwnerExactThenFuzzy() {
        #expect(GitHubRanking.resolveOwner(data, word: "humbl-solutions-ou") == "Humbl-Solutions-OU")
        #expect(GitHubRanking.resolveOwner(data, word: "hum") == "hum")   // exact wins in resolve
        #expect(GitHubRanking.resolveOwner(data, word: "humb") == "Humbl-Solutions-OU")
        #expect(GitHubRanking.resolveOwner(data, word: "zzz") == nil)
    }

    // MARK: repos

    @Test func reposOfOwnerFuzzyBestFirst() {
        let r = GitHubRanking.matchingRepos(data, owner: "Humbl-Solutions-OU", word: "str")
        #expect(r.first == "humbl-streaming")
        #expect(r.contains("infrastructure"))
        #expect(!r.contains("qwok"))
    }

    @Test func reposCaseInsensitiveOwnerAndEmptyWordAlphabetical() {
        #expect(GitHubRanking.matchingRepos(data, owner: "humbl-solutions-ou", word: "")
                == ["humbl-streaming", "humbl.ai", "infrastructure"])
    }

    @Test func limitCapsResults() {
        #expect(GitHubRanking.matchingRepos(data, owner: "Humbl-Solutions-OU", word: "", limit: 2).count == 2)
    }
}
