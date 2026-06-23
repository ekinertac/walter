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

    /// Standard directories where .app bundles live on macOS, including
    /// Homebrew's Caskroom and Cellar on both Apple Silicon and Intel
    /// installs. Standard cask installs additionally symlink to
    /// /Applications, so casks usually appear twice in the raw scan —
    /// bundle-ID dedup in rebuildIndex collapses them down to one.
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
            // Homebrew, Apple Silicon
            "/opt/homebrew/Caskroom",
            "/opt/homebrew/Cellar",
            // Homebrew, Intel
            "/usr/local/Caskroom",
            "/usr/local/Cellar",
        ]
    }()

    /// Dirs scanned recursively. Vendor-installed apps routinely nest one
    /// level deep — `/Applications/Setapp/<app>.app`,
    /// `/Applications/Adobe Photoshop 2024/Adobe Photoshop 2024.app`,
    /// `/Applications/Microsoft Office/<app>.app`, etc. — so a flat scan
    /// of `/Applications` misses them entirely. Homebrew nests at
    /// `<root>/<formula-or-cask>/<version>/<App>.app`, so its Cellar and
    /// Caskroom roots also need recursion. The `findApps` walker treats
    /// `.app` bundles as opaque leaves, so recursion can't fall into a
    /// bundle's internals; bundle-ID dedup collapses any overlap.
    private static let recursiveDirs: Set<String> = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            "/Applications",
            "\(home)/Applications",
            "/opt/homebrew/Caskroom",
            "/opt/homebrew/Cellar",
            "/usr/local/Caskroom",
            "/usr/local/Cellar",
        ]
    }()

    /// Per-root recursion depth cap. Most `recursiveDirs` are shallow
    /// (`/Applications/<vendor>/<App>.app` lives at depth 1), but Homebrew's
    /// Cellar mixes huge non-app trees (Python's stdlib, libexec, etc.)
    /// alongside formula-bundled .app files at the formula+version level.
    /// We need to descend 2 levels (`Cellar/<formula>/<version>/<App>.app`)
    /// to find those — and then stop before walking into the formula's
    /// install tree. Roots not listed here are walked without limit.
    private static let recursionMaxDepth: [String: Int] = [
        "/opt/homebrew/Cellar":   3,
        "/usr/local/Cellar":      3,
        "/opt/homebrew/Caskroom": 3,
        "/usr/local/Caskroom":    3,
    ]

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

    /// Performs a synchronous rebuild and assignment. Used at init for
    /// the initial scan so the launcher has results on first display.
    private func rebuildIndex() {
        allEntries = buildEntries()
        print("AppIndex: \(allEntries.count) apps indexed from \(allDirs.count) directories")
    }

    /// Pure builder — walks scan dirs and returns a fresh entry list.
    /// No mutation of shared state, safe to call from any thread.
    ///
    /// Two-key dedup: paths are deduped first (cheap, prevents reading
    /// the same bundle twice when it appears via overlapping scan dirs),
    /// then bundle IDs are deduped (catches the same logical app surfaced
    /// under different paths — e.g. /System/Applications/Tips.app vs
    /// /System/Library/CoreServices/Tips.app, or the duplicate
    /// Screenshot/Siri/Contacts bundles macOS ships). Scan-dir order is
    /// preserved, so /Applications wins over the CoreServices fallbacks.
    private func buildEntries() -> [AppEntry] {
        var seenPaths = Set<String>()
        var seenBundleIDs = Set<String>()
        var newEntries: [AppEntry] = []

        for dir in allDirs {
            let recursive = Self.recursiveDirs.contains(dir) || extraDirs.contains(dir)
            let maxDepth = Self.recursionMaxDepth[dir] ?? Int.max
            let apps = findApps(in: URL(fileURLWithPath: dir), recursive: recursive, depth: 0, maxDepth: maxDepth)

            for url in apps {
                let path = url.path
                guard !seenPaths.contains(path) else { continue }
                seenPaths.insert(path)

                guard let bundle = Bundle(url: url) else { continue }
                if Self.isInternalAgent(bundle: bundle, at: url) { continue }

                if let bundleID = bundle.bundleIdentifier {
                    guard !seenBundleIDs.contains(bundleID) else { continue }
                    seenBundleIDs.insert(bundleID)
                }

                let name = appDisplayName(bundle: bundle, fallback: url)
                let icon = NSWorkspace.shared.icon(forFile: path)
                icon.size = NSSize(width: 64, height: 64)

                newEntries.append(AppEntry(
                    name: name, path: path,
                    nameLower: name.lowercased(), icon: icon
                ))
            }
        }

        newEntries.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return newEntries
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
    private func findApps(in directory: URL, recursive: Bool, depth: Int = 0, maxDepth: Int = .max) -> [URL] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        ) else { return [] }

        var apps: [URL] = []
        let canRecurse = recursive && depth < maxDepth - 1

        for url in contents {
            if url.pathExtension == "app" {
                apps.append(url)
            } else if canRecurse,
                      (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                // Recurse into subdirectories (but not into .app bundles)
                apps += findApps(in: url, recursive: true, depth: depth + 1, maxDepth: maxDepth)
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
    private static func isInternalAgent(bundle: Bundle, at url: URL) -> Bool {
        let bundleID = bundle.bundleIdentifier
        if let id = bundleID, alwaysIncludeBundleIDs.contains(id) {
            return false
        }

        if let id = bundleID, internalBundleIDs.contains(id) {
            return true
        }

        let info = bundle.infoDictionary ?? [:]

        // An app declares its icon one of several ways, and any of them
        // marks it as a real, user-facing app rather than a headless agent:
        //   * CFBundleIconName   — asset-catalog icon, how every modern
        //                          Xcode-built app ships (no top-level .icns)
        //   * CFBundleIcons / CFBundleIcons~ipad — iOS-on-Mac App Store apps
        //                          (e.g. Tapo), whose bundle is wrapped and
        //                          has no Contents/Resources/*.icns at all
        //   * CFBundleIconFile   — classic .icns reference (checked below)
        // Without this branch, asset-catalog apps and every iOS-on-Mac app
        // were misclassified as agents and silently dropped from the index.
        if info["CFBundleIconName"] != nil ||
           info["CFBundleIcons"] != nil ||
           info["CFBundleIcons~ipad"] != nil {
            return false
        }

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

    /// Reads the display name from a pre-loaded bundle.
    /// Falls back to the filename without .app extension.
    private func appDisplayName(bundle: Bundle, fallback url: URL) -> String {
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

    /// Called by FSEvents when any watched directory changes. The work
    /// hops off the main queue so a noisy installer or fast `make`-reinstall
    /// loop can't stall keystroke handling in the launcher.
    func handleFSEvent() {
        rebuildAsync(qos: .utility)
    }

    /// Safety-net refresh, called when the launcher window is opened.
    /// FSEvents should normally keep the index current, but agent-app
    /// suspension (LSUIElement=true), bursty installers, and queue
    /// coalescing can occasionally let a freshly-installed app slip
    /// past until the next event. The rebuild now runs on a background
    /// queue so `Alt+Tab` is never blocked while we walk the Homebrew
    /// Cellar — the previous synchronous version cost a few hundred ms
    /// at open time and the first keystrokes leaked into the active app.
    func refresh() {
        rebuildAsync(qos: .userInitiated)
    }

    /// Builds a fresh entry list on a background queue, then assigns it
    /// on main. The `allEntries` property is only ever written on the
    /// main queue, so search() and the UI never race with the rebuild.
    private func rebuildAsync(qos: DispatchQoS.QoSClass) {
        DispatchQueue.global(qos: qos).async { [weak self] in
            guard let self else { return }
            let newEntries = self.buildEntries()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.allEntries = newEntries
                self.onChange()
            }
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
