// FrecencyTracker.swift — Frequency + recency ranking for launched apps
//
// Stores launch counts and timestamps in ~/.config/walter/frecency.json.
// The frecency score decays over time so recently-used apps rank higher
// than apps you haven't touched in weeks, even if the latter have more
// total launches.
//
// Formula: score = launchCount * decayFactor
//   where decayFactor = 1.0 for today, 0.9 for yesterday, halves every 7 days.
//
// Called by: LauncherEngine after a successful launch (record),
//           and during search (boost scores).

import Foundation

class FrecencyTracker {

    struct Entry: Codable {
        var count: Int
        var lastUsed: Date
    }

    /// Key = app path, Value = usage data
    private var entries: [String: Entry] = [:]
    private let fileURL: URL

    init() {
        let configDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/walter")
        fileURL = configDir.appendingPathComponent("frecency.json")
        load()
    }

    /// Record a launch. Call this every time the user picks a result.
    func recordLaunch(path: String) {
        var entry = entries[path] ?? Entry(count: 0, lastUsed: Date())
        entry.count += 1
        entry.lastUsed = Date()
        entries[path] = entry
        save()
    }

    /// Returns a frecency score for the given path (0 if never launched).
    /// Higher = more relevant. Used to boost fuzzy match scores.
    func score(for path: String) -> Double {
        guard let entry = entries[path] else { return 0 }

        let daysSince = max(0, -entry.lastUsed.timeIntervalSinceNow / 86400)
        // Half-life of 7 days: score halves every week of inactivity
        let decay = pow(0.5, daysSince / 7.0)
        return Double(entry.count) * decay
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        entries = (try? JSONDecoder().decode([String: Entry].self, from: data)) ?? [:]
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
