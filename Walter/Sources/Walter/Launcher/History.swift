// History.swift — Recent-query history for shell-style up/down recall
//
// Stores the last N queries the user actually acted on (Enter, Cmd+Enter,
// Cmd+1…9, Cmd+C) so they can be recalled with the Up arrow when the
// launcher's input is empty — matching the muscle memory of every shell,
// browser URL bar, and existing launcher.
//
// Intentionally simple:
//   * Append-only ring with a hard cap (oldest entries fall off).
//   * Consecutive duplicates are collapsed at push time.
//   * The cursor is transient — `resetCursor()` is called on every panel
//     show so navigation always starts from "newest" again.
//   * Persistence is best-effort JSON in ~/.config/walter/history.json.
//     Failure to read or write is silently ignored; history is a comfort
//     feature, not data integrity.
//
// Up/Down handling lives in LauncherPanelController; this file just owns
// the array and the cursor.

import Foundation

final class History {

    /// Hard cap on stored entries. Beyond this we drop the oldest — fast
    /// recall doesn't benefit from infinite history and the file should
    /// stay small enough to load in <1ms.
    private static let maxEntries = 50

    private(set) var entries: [String] = []
    /// `nil` means "no history navigation active — the input belongs to
    /// the user." A non-nil value points at the entry currently shown.
    private var cursor: Int? = nil

    private let fileURL: URL

    init() {
        self.fileURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/walter/history.json")
        load()
    }

    // MARK: - Push

    /// Records a query the user acted on. Empty strings and consecutive
    /// duplicates are silently dropped; otherwise the entry is appended
    /// and the cap enforced before saving.
    func push(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        if entries.last == trimmed { return }
        entries.append(trimmed)
        if entries.count > Self.maxEntries {
            entries.removeFirst(entries.count - Self.maxEntries)
        }
        save()
    }

    // MARK: - Navigation

    func resetCursor() {
        cursor = nil
    }

    /// Moves toward older entries. Returns the entry to show, or `nil`
    /// when there is nothing further back to navigate to (caller leaves
    /// the input as-is).
    func previous() -> String? {
        guard !entries.isEmpty else { return nil }
        if let c = cursor {
            // Already navigating — step further back if possible.
            guard c > 0 else { return entries[c] }   // hold at oldest
            cursor = c - 1
        } else {
            // First Up press — show the most recent entry.
            cursor = entries.count - 1
        }
        return entries[cursor!]
    }

    /// Moves toward newer entries. Returns the entry to show, or the
    /// empty string when the user has stepped past the newest entry
    /// (caller clears the input).
    func next() -> String? {
        guard let c = cursor else { return nil }
        if c >= entries.count - 1 {
            // Past the newest — exit history navigation.
            cursor = nil
            return ""
        }
        cursor = c + 1
        return entries[cursor!]
    }

    /// True while the input shows a recalled entry rather than the user's
    /// own typing — used by the controller to decide which keys mean
    /// "exit history" vs "continue navigating."
    var isNavigating: Bool { cursor != nil }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([String].self, from: data) else { return }
        // Cap defensively in case an older build wrote more than the cap.
        if decoded.count > Self.maxEntries {
            entries = Array(decoded.suffix(Self.maxEntries))
        } else {
            entries = decoded
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
