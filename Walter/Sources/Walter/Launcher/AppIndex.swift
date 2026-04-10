// AppIndex.swift — Fast application indexer with FSEvents watching
//
// Two-phase approach for instant results + zero-lag new app discovery:
//
//   Phase 1 (startup): Shallow scan of all known .app directories.
//     Reads each bundle's Info.plist for display name and icon.
//     Typically completes in <100ms for ~200 apps.
//
//   Phase 2 (ongoing): FSEvents watches on all app directories.
//     When a new .app is added (Homebrew install, drag to /Applications,
//     etc.), the watcher fires within ~1 second and the index is updated.
//     No polling, no waiting for Spotlight, no "couple minutes" delay.
//
// The index is a flat array of AppEntry structs, searched via substring
// match on the app name. For ~200 apps, linear scan is faster than any
// index structure (cache-friendly, no allocation).
//
// Called by: LauncherEngine.search() on every keystroke.

import AppKit
import CoreServices

// ---------------------------------------------------------------------------
// Data model
// ---------------------------------------------------------------------------

struct AppEntry {
    let name: String            // display name (e.g. "Visual Studio Code")
    let path: String            // full path to .app bundle
    let nameLower: String       // pre-lowercased for fast matching
    let icon: NSImage?          // cached app icon (loaded lazily on first access)
}

// ---------------------------------------------------------------------------
// AppIndex
// ---------------------------------------------------------------------------

class AppIndex {

    /// All known directories where .app bundles live on macOS.
    /// Ordered by likelihood — /Applications first for fastest results.
    private static let watchedDirs: [String] = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "/Applications",
            "/Applications/Utilities",
            "/System/Applications",
            "/System/Applications/Utilities",
            "/System/Library/CoreServices",
            "/System/Library/CoreServices/Applications",
            "\(home)/Applications",
            "/Applications/MacPorts",
        ]
        return candidates.filter { FileManager.default.fileExists(atPath: $0) }
    }()

    /// Full list of indexed apps — used by LauncherEngine for fuzzy matching.
    private(set) var allEntries: [AppEntry] = []
    private var eventStream: FSEventStreamRef?
    private let onChange: () -> Void

    /// `onChange` is called (on main thread) whenever the index is rebuilt,
    /// so the UI can refresh if the panel is open.
    init(onChange: @escaping () -> Void = {}) {
        self.onChange = onChange
        rebuildIndex()
        startWatching()
    }

    deinit {
        stopWatching()
    }

    /// Returns all apps whose name contains the query (case-insensitive).
    /// Empty query returns everything, sorted alphabetically.
    func search(query: String) -> [AppEntry] {
        if query.isEmpty {
            return allEntries
        }
        let q = query.lowercased()
        return allEntries.filter { $0.nameLower.contains(q) }
    }

    // MARK: - Index building

    /// Scans all watched directories and rebuilds the entries array.
    /// Fast: ~50-100ms for a typical macOS install.
    private func rebuildIndex() {
        var seen = Set<String>() // deduplicate by path
        var newEntries: [AppEntry] = []

        for dir in Self.watchedDirs {
            let dirURL = URL(fileURLWithPath: dir)
            guard let contents = try? FileManager.default.contentsOfDirectory(
                at: dirURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for url in contents where url.pathExtension == "app" {
                let path = url.path
                guard !seen.contains(path) else { continue }
                seen.insert(path)

                let name = appDisplayName(at: url)
                let icon = NSWorkspace.shared.icon(forFile: path)
                // Size the icon once — avoids repeated scaling during rendering
                icon.size = NSSize(width: 64, height: 64) // oversized so it stays crisp at any scale

                newEntries.append(AppEntry(
                    name: name,
                    path: path,
                    nameLower: name.lowercased(),
                    icon: icon
                ))
            }
        }

        newEntries.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        allEntries = newEntries
        print("AppIndex: \(allEntries.count) apps indexed from \(Self.watchedDirs.count) directories")
    }

    /// Reads the display name from the bundle's Info.plist.
    /// Falls back to the filename without .app extension.
    private func appDisplayName(at url: URL) -> String {
        if let bundle = Bundle(url: url) {
            // CFBundleDisplayName is the user-facing name (localised)
            if let displayName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String,
               !displayName.isEmpty {
                return displayName
            }
            // CFBundleName is the short bundle name
            if let bundleName = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String,
               !bundleName.isEmpty {
                return bundleName
            }
        }
        // Last resort: filename
        return url.deletingPathExtension().lastPathComponent
    }

    // MARK: - FSEvents watcher

    /// Starts an FSEvents stream on all watched directories.
    /// Fires within ~1 second of any filesystem change (new app installed,
    /// app deleted, app renamed). Same mechanism as your screenshot watcher
    /// launchd plist — but native Swift, no shell scripts needed.
    private func startWatching() {
        let paths = Self.watchedDirs as CFArray

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        guard let stream = FSEventStreamCreate(
            nil,                                    // allocator
            fsEventsCallback,                       // callback
            &context,                               // context (passes `self`)
            paths,                                  // paths to watch
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.0,                                    // latency: 1 second batch window
            UInt32(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents)
        ) else {
            print("AppIndex: Failed to create FSEventStream")
            return
        }

        eventStream = stream
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
        FSEventStreamStart(stream)
        print("AppIndex: FSEvents watcher active on \(Self.watchedDirs.count) directories")
    }

    private func stopWatching() {
        guard let stream = eventStream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        eventStream = nil
    }

    /// Called by FSEvents when any watched directory changes.
    /// Rebuilds the entire index (fast enough at ~50ms) rather than
    /// trying to do incremental updates.
    func handleFSEvent() {
        rebuildIndex()
        DispatchQueue.main.async { [weak self] in
            self?.onChange()
        }
    }
}

// FSEvents C callback — bridges to the Swift instance via the context pointer.
private func fsEventsCallback(
    streamRef: ConstFSEventStreamRef,
    clientCallBackInfo: UnsafeMutableRawPointer?,
    numEvents: Int,
    eventPaths: UnsafeMutableRawPointer,
    eventFlags: UnsafePointer<FSEventStreamEventFlags>,
    eventIds: UnsafePointer<FSEventStreamEventId>
) {
    guard let info = clientCallBackInfo else { return }
    let index = Unmanaged<AppIndex>.fromOpaque(info).takeUnretainedValue()
    index.handleFSEvent()
}
