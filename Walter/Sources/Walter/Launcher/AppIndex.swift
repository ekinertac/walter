// App discovery is confined to the shared /Applications policy.
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

    /// Full list of indexed apps — used by LauncherEngine for fuzzy matching.
    private(set) var allEntries: [AppEntry] = []
    private var eventStream: FSEventStreamRef?
    private let onChange: () -> Void
    private let apps = AllowedApps()

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

    private var allDirs: [String] { [apps.root.path] }

    private func rebuildIndex() {
        allEntries = buildEntries()
    }

    private func buildEntries() -> [AppEntry] {
        apps.discover().compactMap { url -> AppEntry? in
            guard let bundle = Bundle(url: url) else { return nil }
            let name = appDisplayName(bundle: bundle, fallback: url)
            let icon = NSWorkspace.shared.icon(forFile: url.path).copy() as? NSImage
            icon?.size = NSSize(width: 64, height: 64)
            return AppEntry(name: name, path: url.path, nameLower: name.lowercased(), icon: icon)
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
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
    /// queue so popup input is not blocked while scanning allowed apps.
    /// The previous synchronous version cost a few hundred ms
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
