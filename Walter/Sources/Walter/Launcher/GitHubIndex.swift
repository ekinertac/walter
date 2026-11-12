// GitHubIndex.swift — GitHub owners and repos for prefix-triggered repo search
//
// Typing "repo hum" lists matching owners; Tab completes the selected owner
// ("repo Humbl-Solutions-OU "), then "str" lists that owner's repos and Tab
// completes the repo name. Enter opens the owner or repo page in the browser.
// The trailing space after the owner is what switches from the owner phase
// to the repo phase, so the query must be parsed before any trimming.
//
// Data: every repo the user can access (owner, collaborator, org member),
// plus their login and orgs, fetched through the `gh` CLI so Walter reuses
// the user's existing GitHub auth and never stores a token. The fetch takes
// ~15-20 s for a few hundred repos, so the result is cached on disk in
// ~/.config/walter/.cache/github.json (next to the favicon cache) and
// refreshed in the background when older than 24 h. The stale list is served
// meanwhile.
//
// Called by: LauncherEngine.search (githubResults). Tab handling lives in
// LauncherPanelController and only reads SearchResult.completion.
// Tests: Tests/WalterTests/GitHubIndexTests.swift (pure functions only).

import Foundation

struct GitHubData: Codable, Equatable {
    var login: String
    var orgs: [String]
    var repos: [String]   // "owner/name"
}

enum GitHubQuery: Equatable {
    /// Still typing the owner: "repo hum".
    case owner(String)
    /// Owner done (space typed after it): "repo Humbl-Solutions-OU str".
    case repo(owner: String, word: String)

    /// Parses the text after the prefix, e.g. "hum" or "hum str".
    /// A trailing space after the owner already means the repo phase.
    static func parse(_ rest: String) -> GitHubQuery {
        let trimmedLeading = String(rest.drop(while: { $0 == " " }))
        guard let space = trimmedLeading.firstIndex(of: " ") else {
            return .owner(trimmedLeading)
        }
        let owner = String(trimmedLeading[..<space])
        let word = trimmedLeading[trimmedLeading.index(after: space)...].trimmingCharacters(in: .whitespaces)
        return .repo(owner: owner, word: word)
    }
}

/// Pure ranking over a loaded GitHubData. Kept free of I/O so it is testable.
enum GitHubRanking {
    /// Owners in priority order: the user, then their orgs, then owners of
    /// repos they collaborate on. Each group is alphabetical.
    static func owners(_ data: GitHubData) -> [String] {
        let me = data.login.isEmpty ? [] : [data.login]
        let orgs = data.orgs.sorted { $0.lowercased() < $1.lowercased() }
        let known = Set((me + orgs).map { $0.lowercased() })
        let others = Set(data.repos.compactMap { $0.split(separator: "/").first.map(String.init) })
            .filter { !known.contains($0.lowercased()) }
            .sorted { $0.lowercased() < $1.lowercased() }
        return me + orgs + others
    }

    /// Owners that fuzzy-match `word`, priority group first, then match
    /// score. Priority wins over score so "hum" puts the user's own org above
    /// a collaborator whose name happens to score a little higher.
    static func matchingOwners(_ data: GitHubData, word: String, limit: Int = 25) -> [String] {
        let ordered = owners(data)
        let groupOf = Dictionary(uniqueKeysWithValues: ordered.enumerated().map { i, owner in
            (owner, owner.lowercased() == data.login.lowercased() ? 0
                : data.orgs.contains(where: { $0.lowercased() == owner.lowercased() }) ? 1 : 2)
        })
        if word.isEmpty { return Array(ordered.prefix(limit)) }
        return ordered
            .compactMap { owner -> (String, Int, Int)? in
                let m = fuzzyMatch(query: word, target: owner)
                return m.matched ? (owner, groupOf[owner] ?? 2, m.score) : nil
            }
            .sorted { $0.1 != $1.1 ? $0.1 < $1.1 : $0.2 > $1.2 }
            .prefix(limit)
            .map { $0.0 }
    }

    /// The owner a repo-phase query refers to: an exact (case-insensitive)
    /// match, else the best fuzzy match, so "repo hum str" works without Tab.
    static func resolveOwner(_ data: GitHubData, word: String) -> String? {
        if let exact = owners(data).first(where: { $0.lowercased() == word.lowercased() }) {
            return exact
        }
        return matchingOwners(data, word: word, limit: 1).first
    }

    /// Repo names of `owner` that fuzzy-match `word`, best match first;
    /// alphabetical when `word` is empty.
    static func matchingRepos(_ data: GitHubData, owner: String, word: String, limit: Int = 25) -> [String] {
        let names = data.repos.compactMap { full -> String? in
            let parts = full.split(separator: "/", maxSplits: 1).map(String.init)
            guard parts.count == 2, parts[0].lowercased() == owner.lowercased() else { return nil }
            return parts[1]
        }
        if word.isEmpty {
            return Array(names.sorted { $0.lowercased() < $1.lowercased() }.prefix(limit))
        }
        return names
            .compactMap { name -> (String, Int)? in
                let m = fuzzyMatch(query: word, target: name)
                return m.matched ? (name, m.score) : nil
            }
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.lowercased() < $1.0.lowercased() }
            .prefix(limit)
            .map { $0.0 }
    }
}

/// Loads, caches and refreshes GitHubData. All state is read and written on
/// the main thread; only the `gh` calls run on a background queue.
final class GitHubIndex {

    enum State {
        case ready(GitHubData)
        case loading                 // no cache yet, first fetch running
        case ghMissing               // gh CLI not found
        case failed(String)          // gh ran but failed (usually not logged in)
    }

    private(set) var state: State = .loading
    private var loadedFromDisk = false
    private var isRefreshing = false
    private let onChange: () -> Void
    private let maxAge: TimeInterval = 24 * 3600

    private let cacheURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/walter/.cache/github.json")

    /// GUI apps don't get the shell's PATH, so look in the usual install spots.
    private static let ghCandidates = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/usr/bin/gh"]

    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
    }

    /// Called on every gh-mode keystroke: loads the disk cache once and
    /// starts a background refresh when the cache is missing or stale.
    func ensureFresh() {
        if !loadedFromDisk {
            loadedFromDisk = true
            if let data = try? Data(contentsOf: cacheURL),
               let decoded = try? JSONDecoder().decode(GitHubData.self, from: data) {
                state = .ready(decoded)
            }
        }
        let modified = (try? cacheURL.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate
        let stale = modified.map { Date().timeIntervalSince($0) > maxAge } ?? true
        if stale { refresh() }
    }

    private func refresh() {
        guard !isRefreshing else { return }
        guard let gh = Self.ghCandidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            if case .ready = state { return }   // keep serving the old cache
            state = .ghMissing
            return
        }
        isRefreshing = true
        let cacheURL = self.cacheURL
        DispatchQueue.global(qos: .utility).async {
            let result: Result<GitHubData, Error> = Result {
                let login = try Self.run(gh, ["api", "user", "-q", ".login"]).first ?? ""
                let orgs = try Self.run(gh, ["api", "user/orgs", "--paginate", "-q", ".[].login"])
                let repos = try Self.run(gh, ["api",
                    "user/repos?per_page=100&affiliation=owner,collaborator,organization_member",
                    "--paginate", "-q", ".[].full_name"])
                let data = GitHubData(login: login, orgs: orgs, repos: repos)
                try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(),
                                                        withIntermediateDirectories: true)
                try JSONEncoder().encode(data).write(to: cacheURL, options: .atomic)
                return data
            }
            DispatchQueue.main.async {
                self.isRefreshing = false
                switch result {
                case .success(let data):
                    self.state = .ready(data)
                case .failure(let error):
                    if case .ready = self.state { break }   // keep serving the old cache
                    self.state = .failed(error.localizedDescription)
                }
                self.onChange()
            }
        }
    }

    private struct GhError: LocalizedError {
        let errorDescription: String?
    }

    /// Runs gh and returns its non-empty stdout lines; throws with gh's
    /// stderr on a non-zero exit.
    private static func run(_ gh: String, _ args: [String]) throws -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: gh)
        process.arguments = args
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()
        // Read before waiting: a full pipe buffer would otherwise block gh forever.
        let stdout = out.fileHandleForReading.readDataToEndOfFile()
        let stderr = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(decoding: stderr, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            throw GhError(errorDescription: message.isEmpty ? "gh exited with \(process.terminationStatus)" : message)
        }
        return String(decoding: stdout, as: UTF8.self).split(separator: "\n").map(String.init)
    }
}
