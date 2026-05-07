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

    /// Standard directories where .app bundles live on macOS.
    private static let defaultDirs: [String] = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            "/Applications",
            "/Applications/Utilities",
            "/System/Applications",
            "/System/Applications/Utilities",
            "/System/Library/CoreServices",
            "/System/Library/CoreServices/Applications",
            "\(home)/Applications",
            "/Applications/MacPorts",
        ]
    }()

    /// Dirs that should be scanned recursively (user-level app folders
    /// may have subfolders like ~/Applications/Setapp/).
    private static let recursiveDirs: Set<String> = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return ["\(home)/Applications"]
    }()

    /// Full list of indexed apps — used by LauncherEngine for fuzzy matching.
    private(set) var allEntries: [AppEntry] = []
    private var eventStream: FSEventStreamRef?
    private let onChange: () -> Void
    private var extraDirs: [String] = []

    init(extraDirs: [String] = [], onChange: @escaping () -> Void = {}) {
        self.onChange = onChange
        self.extraDirs = extraDirs
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
    /// All directories to scan = defaults + extra from config.
    private var allDirs: [String] {
        let combined = Self.defaultDirs + extraDirs
        return combined.filter { FileManager.default.fileExists(atPath: $0) }
    }

    /// Bundle IDs of /System/Library/CoreServices apps that LaunchServices
    /// reports as launchable but are really internal helpers, agents, or
    /// tutorial overlays. They have no business in a launcher.
    /// Add to this list when new offenders are discovered — the user's
    /// `excluded_apps` config is the override path for personal taste.
    private static let internalBundleIDs: Set<String> = [
        "com.apple.AVB-Audio-Configuration",
    ]

    /// Bundle IDs to keep even when the icon-presence heuristic would
    /// reject them. Many first-party macOS apps (especially on macOS 13+)
    /// declare their icon via AssetCatalog rather than CFBundleIconFile,
    /// which would otherwise drop them from the index.
    /// Whitelist over heuristic — false positives in this list cost less
    /// than missing user-facing apps.
    private static let alwaysIncludeBundleIDs: Set<String> = [
        // System / configuration
        "com.apple.systempreferences",      // System Settings
        "com.apple.SystemProfiler",         // System Information
        "com.apple.ActivityMonitor",
        "com.apple.DiskUtility",
        "com.apple.Console",
        "com.apple.keychainaccess",         // Keychain Access
        "com.apple.AirPortUtility",
        "com.apple.audio.AudioMIDISetup",
        "com.apple.bluetoothfileexchange",
        "com.apple.bootcampassistant",
        "com.apple.ColorSyncUtility",
        "com.apple.DigitalColorMeter",
        "com.apple.MigrationAssistant",
        "com.apple.VoiceOverUtility",
        "com.apple.screencaptureui",        // Screenshot
        "com.apple.ScriptEditor2",
        "com.apple.grapher",
        "com.apple.Terminal",
        // Productivity / built-ins commonly bundled without CFBundleIconFile
        "com.apple.finder",                 // Finder (paranoia)
        "com.apple.Safari",
        "com.apple.mail",
        "com.apple.AddressBook",            // Contacts
        "com.apple.iCal",                   // Calendar
        "com.apple.reminders",
        "com.apple.Notes",
        "com.apple.Maps",
        "com.apple.FaceTime",
        "com.apple.iChat",                  // Messages
        "com.apple.shortcuts",
        "com.apple.Stickies",
        "com.apple.TextEdit",
        "com.apple.Preview",
        "com.apple.QuickTimePlayerX",
        "com.apple.Music",
        "com.apple.podcasts",
        "com.apple.TV",
        "com.apple.weather",
        "com.apple.Stocks",
        "com.apple.Home",
        "com.apple.iWork.Pages",
        "com.apple.iWork.Numbers",
        "com.apple.iWork.Keynote",
        "com.apple.dt.Xcode",
        "com.apple.FontBook",
        "com.apple.calculator",
        "com.apple.Image_Capture",
        "com.apple.PhotoBooth",
        "com.apple.dictionary",
        "com.apple.AppStore",
        "com.apple.iBooksX",                // Books
        "com.apple.Photos",
        "com.apple.findmy",
    ]

    private func rebuildIndex() {
        var seen = Set<String>()
        var newEntries: [AppEntry] = []

        for dir in allDirs {
            let recursive = Self.recursiveDirs.contains(dir) || extraDirs.contains(dir)
            let apps = findApps(in: URL(fileURLWithPath: dir), recursive: recursive)

            for url in apps {
                let path = url.path
                guard !seen.contains(path) else { continue }
                seen.insert(path)

                if Self.isInternalAgent(at: url) { continue }

                let name = appDisplayName(at: url)
                let icon = NSWorkspace.shared.icon(forFile: path)
                icon.size = NSSize(width: 64, height: 64)

                newEntries.append(AppEntry(
                    name: name, path: path,
                    nameLower: name.lowercased(), icon: icon
                ))
            }
        }

        newEntries.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        allEntries = newEntries
        print("AppIndex: \(allEntries.count) apps indexed from \(allDirs.count) directories")
    }

    /// Finds .app bundles in a directory. When `recursive` is true, also
    /// scans subfolders (e.g. ~/Applications/Setapp/*.app) — but stops
    /// recursing into .app bundles themselves (they contain nested .app).
    ///
    /// We deliberately do NOT pass `.skipsHiddenFiles` here. macOS marks
    /// the Cryptex-target symlinks under /Applications (Safari.app and a
    /// handful of other system browsers) as hidden so they don't clutter
    /// Finder, and that flag is honored by contentsOfDirectory. With the
    /// option enabled, `Safari.app -> ../System/Cryptexes/...` is silently
    /// dropped from the listing and never makes it into the index.
    /// Filtering by `.app` extension is enough — dotfiles are uninteresting.
    private func findApps(in directory: URL, recursive: Bool) -> [URL] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        ) else { return [] }

        var apps: [URL] = []

        for url in contents {
            if url.pathExtension == "app" {
                apps.append(url)
            } else if recursive,
                      (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                // Recurse into subdirectories (but not into .app bundles)
                apps += findApps(in: url, recursive: true)
            }
        }

        return apps
    }

    /// Returns true if the bundle is an internal helper that should not
    /// appear in launcher results. Heuristics:
    ///   1. No CFBundleIconFile declared in Info.plist (most agents).
    ///   2. CFBundleIconFile names a file that doesn't exist on disk
    ///      (rare, but a strong signal it isn't user-facing).
    ///   3. Bundle ID is in the hardcoded internal list (AVB and friends
    ///      that *do* ship icons but exist only for niche subsystems).
    private static func isInternalAgent(at url: URL) -> Bool {
        guard let bundle = Bundle(url: url) else { return true }

        let bundleID = bundle.bundleIdentifier
        if let id = bundleID, alwaysIncludeBundleIDs.contains(id) {
            return false
        }

        if let id = bundleID, internalBundleIDs.contains(id) {
            return true
        }

        let info = bundle.infoDictionary ?? [:]
        guard let iconRef = info["CFBundleIconFile"] as? String, !iconRef.isEmpty else {
            return true
        }

        // CFBundleIconFile may or may not include the .icns extension.
        let iconName = iconRef.hasSuffix(".icns") ? iconRef : iconRef + ".icns"
        let iconPath = url.appendingPathComponent("Contents/Resources/\(iconName)").path
        if !FileManager.default.fileExists(atPath: iconPath) {
            return true
        }

        return false
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
        let paths = allDirs as CFArray

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
        print("AppIndex: FSEvents watcher active on \(allDirs.count) directories")
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
