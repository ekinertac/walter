// QwokIndex.swift — local dev apps registered in qwok, for prefix-triggered URL search
//
// Typing "qwok b2" lists matching qwok apps that have a URL; Tab completes the name and
// Enter opens the app's URL in the browser, also when the app is stopped.
//
// Data: the table printed by `qwok list`. qwok is the only place that knows
// the right URL (scheme and port depend on the running portless proxy), and
// its published stdout is treated as a stable format. Rows without a URL
// and anything that does not look like a row are skipped.
//
// Called by: LauncherEngine.search.
// Related: GitHubIndex.swift (same prefix and Tab pattern).
// Tests: Tests/WalterTests/QwokIndexTests.swift.

import Foundation

struct QwokApp: Equatable {
    let name: String
    let url: String
}

/// Pure parsing and ranking. Kept free of I/O so it is testable.
enum QwokList {
    /// The text after the prefix and its space ("b2" for "qwok b2"), or nil
    /// when `query` is not a qwok query. An empty prefix turns the mode off.
    static func word(in query: String, prefix: String) -> String? {
        let leading = query.drop(while: { $0 == " " })
        guard !prefix.isEmpty, leading.lowercased().hasPrefix(prefix.lowercased() + " ") else { return nil }
        return leading.dropFirst(prefix.count + 1).trimmingCharacters(in: .whitespaces)
    }

    /// Apps with a URL in the `qwok list` table (NAME TYPE STATUS URL PORT).
    /// Desktop apps have one only when their .qwok.toml names it, else "—".
    /// The header, "—" rows and messages fail the checks.
    static func parse(_ output: String) -> [QwokApp] {
        output.split(whereSeparator: \.isNewline).compactMap { line in
            let fields = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard fields.count >= 4, ["web", "app"].contains(fields[1]),
                  fields[3].hasPrefix("http://") || fields[3].hasPrefix("https://") else { return nil }
            return QwokApp(name: fields[0], url: fields[3])
        }
    }

    /// Apps that fuzzy-match `word`, best match first; alphabetical when
    /// `word` is empty (every score is 0 then).
    static func matching(_ apps: [QwokApp], word: String, limit: Int = 25) -> [QwokApp] {
        Array(apps
            .compactMap { app -> (app: QwokApp, score: Int)? in
                let m = fuzzyMatch(query: word, target: app.name)
                return m.matched ? (app, m.score) : nil
            }
            .sorted { $0.score != $1.score ? $0.score > $1.score
                : $0.app.name.lowercased() < $1.app.name.lowercased() }
            .prefix(limit)
            .map(\.app))
    }
}

/// Runs `qwok list` and keeps the result in memory. All state is read and
/// written on the main thread; only the process runs on a background queue.
final class QwokIndex {

    enum State: Equatable {
        case ready([QwokApp])
        case loading                 // first fetch not finished
        case qwokMissing             // qwok not found
        case failed(String)          // qwok ran but failed
    }

    private(set) var state: State = .loading
    private(set) var isRefreshing = false
    private var isStale = true
    private let candidates: [String]
    private let onChange: () -> Void

    private static let binDirs = ["/opt/homebrew/bin", "/usr/local/bin"]

    /// GUI apps don't get the shell's PATH, so look in the usual install spots.
    static let defaultCandidates = binDirs.map { $0 + "/qwok" }

    init(candidates: [String] = QwokIndex.defaultCandidates, onChange: @escaping () -> Void) {
        self.candidates = candidates
        self.onChange = onChange
    }

    /// Marks the list as old. The next `ensureFresh` fetches it again, so
    /// opening Walter without a qwok query never starts a process.
    func invalidate() {
        isStale = true
    }

    /// Called on every qwok-mode keystroke: fetches when the list is old. The
    /// old list is served meanwhile.
    func ensureFresh() {
        guard isStale, !isRefreshing else { return }
        // Cleared at the start, not the end, so that an `invalidate` during
        // the fetch still causes another one.
        isStale = false
        guard let qwok = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            if case .ready = state { return }   // keep serving the old list
            state = .qwokMissing
            return
        }
        isRefreshing = true
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { QwokList.parse(try Self.run(qwok, ["list"])) }
            DispatchQueue.main.async {
                self.isRefreshing = false
                let old = self.state
                switch result {
                case .success(let apps):
                    self.state = .ready(apps)
                case .failure(let error):
                    if case .ready = old { break }   // keep serving the old list
                    self.state = .failed(error.localizedDescription)
                }
                if self.state != old { self.onChange() }
            }
        }
    }

    /// Environment for qwok. qwok runs `portless` by name to get each URL;
    /// with the PATH of a GUI app it does not find it and prints a fallback
    /// URL that can have the wrong port.
    static func environment(_ base: [String: String]) -> [String: String] {
        var env = base
        env["PATH"] = (binDirs + [base["PATH"] ?? "/usr/bin:/bin"]).joined(separator: ":")
        return env
    }

    private struct QwokError: LocalizedError {
        let errorDescription: String?
    }

    /// Runs qwok and returns its stdout; throws with its stderr on a
    /// non-zero exit. Same shape as GitHubIndex.run.
    private static func run(_ qwok: String, _ args: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: qwok)
        process.arguments = args
        process.environment = environment(ProcessInfo.processInfo.environment)
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()
        // Read before waiting: a full pipe buffer would otherwise block qwok forever.
        let stdout = out.fileHandleForReading.readDataToEndOfFile()
        let stderr = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(decoding: stderr, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            throw QwokError(errorDescription: message.isEmpty ? "qwok exited with \(process.terminationStatus)" : message)
        }
        return String(decoding: stdout, as: UTF8.self)
    }
}
