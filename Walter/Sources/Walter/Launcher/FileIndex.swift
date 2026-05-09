// FileIndex.swift — Filename index for prefix-triggered file search
//
// Walter intentionally does not index the whole disk. Spotlight already
// does that, and it's fundamentally not what a focused launcher should
// do. This index is opt-in: the user lists the directories they actually
// want searchable under `[search] file_dirs` (e.g. ~/Documents, ~/Desktop,
// ~/Downloads), and Walter mirrors them into an in-memory filename
// catalog plus an FSEvents watcher so adds/removes/renames take effect
// inside a second.
//
// The mechanics mirror AppIndex.swift — same FSEvents pattern, same
// fuzzy-search interface — but with two important differences:
//
//   * File icons are NOT eager-loaded. The index can hold tens of
//     thousands of entries; loading icons up front would cost memory and
//     boot time for files most users never search for. Icons are pulled
//     via NSWorkspace at result-build time, only for the few entries
//     that survive fuzzy matching.
//
//   * Some directories are toxic to recurse into. `.git`, `node_modules`,
//     `Library`, build outputs, and Apple bundles are skipped wholesale.
//     The launcher is for the user's documents, not their dependency
//     trees.
//
// Triggered from LauncherEngine.search() when the query starts with `'`
// (the prefix character). Outside of prefix mode, this index is
// invisible to the user — apps stay the first-class result type.

import AppKit
import CoreServices

struct FileEntry {
    let name: String        // filename (e.g. "report.pdf")
    let path: String        // absolute path
    let nameLower: String
}

final class FileIndex {

    /// Subdirectory names that are never recursed into. These are either
    /// noise (build outputs, dependencies) or systemically large
    /// (Library) and don't represent user-authored content.
    private static let skipDirNames: Set<String> = [
        ".git", ".svn", ".hg",
        "node_modules", ".build", "build", "dist", "target",
        "Pods", ".bundle", ".cache", ".DS_Store",
        "Library",   // iCloud, Caches, Containers — not what users mean by "files"
    ]

    /// File extensions that are in fact bundles on macOS and would
    /// blow up the index if recursed into. We treat them as opaque
    /// leaves so the user can still find e.g. `Project.app` inside
    /// `~/Desktop` without flooding the index with bundle internals.
    private static let bundleExtensions: Set<String> = [
        "app", "bundle", "framework", "kext", "plugin", "xpc",
        "appex", "rtfd", "photoslibrary", "musiclibrary", "tvlibrary",
        "fcpbundle", "logicx", "garageband",
    ]

    /// Hard cap on the index size. The whole point of this feature is
    /// to stay focused; if the user has pointed us at a tree containing
    /// half a million files we stop indexing instead of consuming
    /// gigabytes of memory.
    private static let maxEntries = 50_000

    private(set) var allEntries: [FileEntry] = []
    private var dirs: [String] = []
    private var eventStream: FSEventStreamRef?
    private let onChange: () -> Void

    init(dirs: [String], onChange: @escaping () -> Void = {}) {
        self.dirs = dirs.map(Self.expand)
        self.onChange = onChange
        rebuildIndex()
        startWatching()
    }

    deinit {
        stopWatching()
    }

    /// Returns fuzzy-matched files for the query. Caller is responsible
    /// for sorting the score-ordered list.
    func search(query: String) -> [(entry: FileEntry, score: Int)] {
        guard !query.isEmpty else { return [] }
        return allEntries.compactMap { entry in
            let result = fuzzyMatch(query: query, target: entry.name)
            guard result.matched else { return nil }
            return (entry, result.score)
        }
    }

    // MARK: - Index building

    private func rebuildIndex() {
        var entries: [FileEntry] = []
        let fm = FileManager.default
        for dir in dirs where fm.fileExists(atPath: dir) {
            walk(URL(fileURLWithPath: dir), into: &entries)
            if entries.count >= Self.maxEntries { break }
        }
        if entries.count >= Self.maxEntries {
            print("FileIndex: hit \(Self.maxEntries) cap — narrow `file_dirs` for cleaner results")
        }
        allEntries = entries
        print("FileIndex: \(allEntries.count) files indexed across \(dirs.count) directories")
    }

    /// Recursive directory walk with bundle/skip-dir pruning. We pass
    /// `entries` by inout so the early-exit cap check is cheap.
    private func walk(_ url: URL, into entries: inout [FileEntry]) {
        if entries.count >= Self.maxEntries { return }

        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for child in contents {
            if entries.count >= Self.maxEntries { return }

            let name = child.lastPathComponent
            let isDir = (try? child.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            let ext = child.pathExtension.lowercased()

            if isDir {
                if Self.skipDirNames.contains(name) { continue }
                if Self.bundleExtensions.contains(ext) {
                    // Treat the bundle as a single leaf entry rather than
                    // recursing into it.
                    entries.append(FileEntry(
                        name: name,
                        path: child.path,
                        nameLower: name.lowercased()
                    ))
                    continue
                }
                walk(child, into: &entries)
            } else {
                entries.append(FileEntry(
                    name: name,
                    path: child.path,
                    nameLower: name.lowercased()
                ))
            }
        }
    }

    // MARK: - FSEvents

    private func startWatching() {
        guard !dirs.isEmpty else { return }
        let paths = dirs as CFArray

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        guard let stream = FSEventStreamCreate(
            nil,
            fileIndexFSEventsCallback,
            &context,
            paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            // Slightly slower latency than AppIndex — file changes are
            // less time-sensitive than installs and we want to coalesce
            // bursts (saving a Word doc fires several events).
            2.0,
            UInt32(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents)
        ) else {
            print("FileIndex: Failed to create FSEventStream")
            return
        }

        eventStream = stream
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
        FSEventStreamStart(stream)
        print("FileIndex: FSEvents watcher active on \(dirs.count) directories")
    }

    private func stopWatching() {
        guard let stream = eventStream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        eventStream = nil
    }

    /// Internal callback target — public to satisfy the C callback bridge.
    func handleFSEvent() {
        rebuildIndex()
        DispatchQueue.main.async { [weak self] in
            self?.onChange()
        }
    }

    // MARK: - Helpers

    /// Expands a leading `~` to the user's home directory. Mirrors the
    /// behavior of `app_dirs` parsing in ConfigManager so users don't
    /// have to remember which expansion happens where.
    private static func expand(_ path: String) -> String {
        if path.hasPrefix("~") {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            return home + String(path.dropFirst())
        }
        return path
    }
}

// FSEvents C callback — bridges to Swift via the context pointer.
private func fileIndexFSEventsCallback(
    streamRef: ConstFSEventStreamRef,
    clientCallBackInfo: UnsafeMutableRawPointer?,
    numEvents: Int,
    eventPaths: UnsafeMutableRawPointer,
    eventFlags: UnsafePointer<FSEventStreamEventFlags>,
    eventIds: UnsafePointer<FSEventStreamEventId>
) {
    guard let info = clientCallBackInfo else { return }
    let index = Unmanaged<FileIndex>.fromOpaque(info).takeUnretainedValue()
    index.handleFSEvent()
}
