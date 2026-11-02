// In-memory app snapshots. All discovery/metadata/icon preparation is worker-only.
import AppKit

struct AppEntry {
    let name: String
    let path: String
    let nameLower: String
    let icon: PreparedIcon?
}

/// Main-queue coordinator. One active scan, at most one coalesced follow-up for
/// filesystem changes. Opening/searching only reads the last published snapshot.
final class AppIndex {
    private(set) var allEntries: [AppEntry] = []
    private(set) var isRefreshing = false
    private let builder: AppIndexBuilding
    private let watcher: AppIndexWatching
    private let onChange: () -> Void
    private let diagnostic: (String) -> Void
    private let clock: () -> TimeInterval
    private let popupInterval: TimeInterval
    private let debounceInterval: TimeInterval
    private let queue = DispatchQueue(label: "walter.apps", qos: .utility)
    private var lastCompletedAt: TimeInterval?
    private var debounce: DispatchWorkItem?
    private var pendingInvalidation = AppIndexInvalidation()
    private var pendingFilesystem = false
    private var filesystemReady = false
    private var restartWatcher = false
    private var stopped = false

    convenience init(policy: AllowedApps = AllowedApps(), onChange: @escaping () -> Void = {}) {
        self.init(builder: CachedAppIndexBuilder(policy: policy),
                  watcher: FSEventsAppIndexWatcher(root: policy.root), onChange: onChange)
    }

    /// Test dependencies avoid real app scanning, native icon calls, and watchers.
    init(builder: AppIndexBuilding, watcher: AppIndexWatching,
         clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         popupInterval: TimeInterval = 30, debounceInterval: TimeInterval = 0.2,
         diagnostic: @escaping (String) -> Void = { print($0) },
         onChange: @escaping () -> Void = {}) {
        self.builder = builder
        self.watcher = watcher
        self.clock = clock
        self.popupInterval = popupInterval
        self.debounceInterval = debounceInterval
        self.diagnostic = diagnostic
        self.onChange = onChange
        dispatchPrecondition(condition: .onQueue(.main))
        startWatching() // Watch first, then scan: no scan-to-watch startup gap.
        beginScan(notifyResults: true, invalidation: AppIndexInvalidation(all: true))
    }

    deinit { stop() }

    /// Call after showing the popup. Constant-time scheduling only: no file or
    /// icon work, no waiting, and no result-list rebuild when this scan completes.
    func refreshForPopup() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard !stopped, !isRefreshing, !pendingFilesystem,
              lastCompletedAt.map({ clock() - $0 >= popupInterval }) ?? true else { return }
        beginScan(notifyResults: false, invalidation: AppIndexInvalidation())
    }

    private func startWatching() {
        if !watcher.start(onChange: { [weak self] event in self?.filesystemChanged(event) }) {
            diagnostic("AppIndex: filesystem watcher could not start; background popup refreshes remain available.")
        }
    }

    private func filesystemChanged(_ event: AppIndexEvent) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard !stopped else { return }
        pendingFilesystem = true
        pendingInvalidation.merge(paths: event.paths, all: event.invalidateAll || event.paths.isEmpty)
        restartWatcher = restartWatcher || event.restartWatcher
        // A bounded coalescing window avoids both event-storm queue growth and
        // indefinite trailing-edge debounce starvation during a long install.
        guard debounce == nil, !filesystemReady else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.stopped else { return }
            self.debounce = nil
            self.filesystemReady = true
            self.startPendingFilesystemScan()
        }
        debounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval, execute: work)
    }

    private func startPendingFilesystemScan() {
        guard !stopped, !isRefreshing, pendingFilesystem, filesystemReady else { return }
        if restartWatcher {
            // Not inside the FSEvents callback: safely replace a root-changed stream.
            startWatching()
            restartWatcher = false
        }
        let invalidation = pendingInvalidation
        pendingInvalidation = AppIndexInvalidation()
        pendingFilesystem = false
        filesystemReady = false
        beginScan(notifyResults: true, invalidation: invalidation)
    }

    private func beginScan(notifyResults: Bool, invalidation: AppIndexInvalidation) {
        isRefreshing = true
        let builder = self.builder
        queue.async { [weak self] in
            let entries = builder.build(invalidation: invalidation)
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.stopped else { return }
                // Entries/images are fully prepared. Main only swaps the snapshot.
                self.allEntries = entries
                self.isRefreshing = false
                self.lastCompletedAt = self.clock()
                if notifyResults { self.onChange() }
                self.startPendingFilesystemScan()
            }
        }
    }

    /// Pending timer/watch callbacks cannot revive the index after teardown.
    /// An already-running finite worker scan may finish, but cannot publish.
    func stop() {
        guard !stopped else { return }
        stopped = true
        debounce?.cancel()
        debounce = nil
        watcher.stop()
    }
}
