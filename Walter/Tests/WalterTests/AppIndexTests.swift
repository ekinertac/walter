import AppKit
import CoreServices
import Foundation
import Testing
@testable import Walter

// No production watcher, /Applications scan, NSWorkspace call, or app lifecycle.
private final class FakeIndexWatcher: AppIndexWatching {
    private let lock = NSLock()
    private var count = 0
    private var handler: ((AppIndexEvent) -> Void)?
    var succeeds = true // Set on main before constructing the index.
    private(set) var stops = 0
    var starts: Int { lock.lock(); defer { lock.unlock() }; return count }
    func start(onChange: @escaping (AppIndexEvent) -> Void) -> Bool {
        lock.lock(); count += 1; lock.unlock()
        handler = succeeds ? onChange : nil
        return succeeds
    }
    func stop() { stops += 1; handler = nil }
    func emit(_ event: AppIndexEvent) { handler?(event) }
    var savedHandler: ((AppIndexEvent) -> Void)? { handler }
}

private final class ControlledIndexBuilder: AppIndexBuilding {
    private let condition = NSCondition()
    private let blocked: Set<Int>
    private var released: Set<Int> = []
    private var releaseEverything = false
    private var requests: [AppIndexInvalidation] = []
    private var mainThreadCalls = 0
    private var completions = 0
    let watcher: FakeIndexWatcher
    private var watchedBeforeScan = true

    init(watcher: FakeIndexWatcher, blocked: Set<Int> = []) {
        self.watcher = watcher
        self.blocked = blocked
    }
    var count: Int { condition.lock(); defer { condition.unlock() }; return requests.count }
    var completed: Int { condition.lock(); defer { condition.unlock() }; return completions }
    var allOffMain: Bool { condition.lock(); defer { condition.unlock() }; return mainThreadCalls == 0 }
    var watcherWasStarted: Bool { condition.lock(); defer { condition.unlock() }; return watchedBeforeScan }
    func request(_ number: Int) -> AppIndexInvalidation {
        condition.lock(); defer { condition.unlock() }; return requests[number - 1]
    }
    func release(_ number: Int) { condition.lock(); released.insert(number); condition.broadcast(); condition.unlock() }
    func releaseAll() { condition.lock(); releaseEverything = true; condition.broadcast(); condition.unlock() }

    func build(invalidation: AppIndexInvalidation) -> [AppEntry] {
        condition.lock()
        requests.append(invalidation)
        let number = requests.count
        if Thread.isMainThread { mainThreadCalls += 1 }
        watchedBeforeScan = watchedBeforeScan && watcher.starts > 0
        while blocked.contains(number) && !released.contains(number) && !releaseEverything { condition.wait() }
        completions += 1
        condition.unlock()
        return [AppEntry(name: "Snapshot \(number)", path: "/unused/Snapshot\(number).app", nameLower: "snapshot \(number)", icon: nil)]
    }
}

@Suite("Background app-index scheduling (mock scan/watcher/clock)")
@MainActor
struct AppIndexTests {
    private func waitUntil(_ predicate: () -> Bool) async throws {
        for _ in 0..<150 {
            if predicate() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        try #require(predicate(), "Timed out waiting for finite mocked index work")
    }

    @Test func startupPopupThrottleAndSilentSnapshotPublication() async throws {
        let watcher = FakeIndexWatcher()
        let builder = ControlledIndexBuilder(watcher: watcher, blocked: [1, 2])
        var now: TimeInterval = 0
        var changes = 0
        var callbacksOnMain = true
        let index = AppIndex(builder: builder, watcher: watcher, clock: { now },
            onChange: { changes += 1; callbacksOnMain = callbacksOnMain && Thread.isMainThread })
        defer { builder.releaseAll(); index.stop() }
        try await waitUntil { builder.count == 1 }
        for _ in 0..<100 { index.refreshForPopup() }
        #expect(index.allEntries.isEmpty)
        #expect(builder.count == 1)
        #expect(builder.watcherWasStarted)
        builder.release(1)
        try await waitUntil { !index.isRefreshing }
        #expect(index.allEntries.first?.name == "Snapshot 1")
        #expect(changes == 1)
        now = 29
        index.refreshForPopup()
        #expect(!index.isRefreshing)
        now = 30
        index.refreshForPopup()
        for _ in 0..<100 { index.refreshForPopup() }
        try await waitUntil { builder.count == 2 }
        #expect(index.allEntries.first?.name == "Snapshot 1") // No wait for the worker.
        #expect(changes == 1)
        builder.release(2)
        try await waitUntil { !index.isRefreshing }
        // New queries read the new snapshot, but visible results were not rebuilt.
        #expect(index.allEntries.first?.name == "Snapshot 2")
        #expect(changes == 1)
        now = 59
        index.refreshForPopup()
        #expect(!index.isRefreshing)
        now = 60
        index.refreshForPopup()
        try await waitUntil { builder.count == 3 && !index.isRefreshing }
        #expect(changes == 1)
        #expect(builder.allOffMain)
        #expect(callbacksOnMain)
    }

    @Test func eventStormDuringPopupScanQueuesOnlyOneFollowup() async throws {
        let watcher = FakeIndexWatcher()
        let builder = ControlledIndexBuilder(watcher: watcher, blocked: [2, 3])
        var now: TimeInterval = 0
        var changes = 0
        let index = AppIndex(builder: builder, watcher: watcher, clock: { now },
            debounceInterval: 0.01, onChange: { changes += 1 })
        defer { builder.releaseAll(); index.stop() }
        try await waitUntil { !index.isRefreshing }
        now = 30
        index.refreshForPopup()
        try await waitUntil { builder.count == 2 }
        for _ in 0..<100 {
            watcher.emit(AppIndexEvent(paths: ["/unused/A.app/Contents/Resources/Icon.icns"]))
            watcher.emit(AppIndexEvent(paths: ["/unused/B.app"]))
        }
        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(builder.count == 2)
        builder.release(2)
        try await waitUntil { builder.count == 3 }
        #expect(changes == 1) // Popup scan completion still must not refresh UI.
        #expect(builder.request(3).paths == ["/unused/A.app/Contents/Resources/Icon.icns", "/unused/B.app"])
        builder.release(3)
        try await waitUntil { !index.isRefreshing }
        try await Task.sleep(nanoseconds: 30_000_000)
        #expect(builder.count == 3)
        #expect(changes == 2) // Startup and the coalesced filesystem refresh only.
        #expect(builder.allOffMain)
    }

    @Test func eventDebounceRecoveryAndWatcherFailureDiagnostics() async throws {
        let watcher = FakeIndexWatcher()
        let builder = ControlledIndexBuilder(watcher: watcher)
        var changes = 0
        let index = AppIndex(builder: builder, watcher: watcher, debounceInterval: 0.01,
                             onChange: { changes += 1 })
        defer { index.stop() }
        try await waitUntil { !index.isRefreshing }
        for _ in 0..<100 { watcher.emit(AppIndexEvent(paths: ["/unused/App.app"])) }
        #expect(builder.count == 1) // No synchronous event scanning.
        try await waitUntil { builder.count == 2 && !index.isRefreshing }
        #expect(changes == 2)
        watcher.emit(AppIndexEvent(paths: ["/unused"], invalidateAll: true, restartWatcher: true))
        try await waitUntil { builder.count == 3 && !index.isRefreshing }
        #expect(watcher.starts == 2)
        #expect(builder.request(3).all)
        index.stop()

        let failing = FakeIndexWatcher(); failing.succeeds = false
        let fallbackBuilder = ControlledIndexBuilder(watcher: failing)
        var diagnostics: [String] = []
        var now: TimeInterval = 0
        let fallback = AppIndex(builder: fallbackBuilder, watcher: failing, clock: { now },
                                diagnostic: { diagnostics.append($0) })
        defer { fallback.stop() }
        try await waitUntil { !fallback.isRefreshing }
        #expect(diagnostics.count == 1)
        now = 31
        fallback.refreshForPopup()
        try await waitUntil { fallbackBuilder.count == 2 && !fallback.isRefreshing }
        #expect(fallback.allEntries.first?.name == "Snapshot 2")
    }

    @Test func stoppedIndexIgnoresWorkerCompletionAndLateEvents() async throws {
        let watcher = FakeIndexWatcher()
        let builder = ControlledIndexBuilder(watcher: watcher, blocked: [1])
        var changes = 0
        let index = AppIndex(builder: builder, watcher: watcher, debounceInterval: 0.01,
                             onChange: { changes += 1 })
        defer { builder.releaseAll(); index.stop() }
        try await waitUntil { builder.count == 1 }
        let lateEvent = watcher.savedHandler
        watcher.emit(AppIndexEvent(paths: ["/unused/App.app"]))
        index.stop()
        lateEvent?(AppIndexEvent(paths: ["/unused/App.app"]))
        index.refreshForPopup()
        builder.release(1)
        try await waitUntil { builder.completed == 1 }
        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(builder.count == 1)
        #expect(index.allEntries.isEmpty)
        #expect(changes == 0)
        #expect(watcher.stops > 0)
    }

    @Test func localFixtureDiscoveryMetadataAndIconsArePreparedOnWorker() async throws {
        let fixture = try TemporaryDirectory()
        let root = fixture.file("Applications")
        let app = root.appendingPathComponent("Fixture.app")
        let contents = app.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        func writeName(_ name: String) throws {
            let data = try PropertyListSerialization.data(fromPropertyList:
                ["CFBundlePackageType": "APPL", "CFBundleName": name], format: .xml, options: 0)
            try data.write(to: contents.appendingPathComponent("Info.plist"), options: .atomic)
        }
        try writeName("Initial")
        let lock = NSLock()
        var iconCalls = 0
        var iconsOffMain = true
        let builder = CachedAppIndexBuilder(policy: AllowedApps(root: root), loadIcon: { _ in
            lock.lock(); defer { lock.unlock() }
            iconCalls += 1
            iconsOffMain = iconsOffMain && !Thread.isMainThread
            return IconFixture.icon() // Never invoke NSWorkspace, even for a synthetic bundle.
        })
        var now: TimeInterval = 0
        let index = AppIndex(builder: builder, watcher: FakeIndexWatcher(), clock: { now })
        defer { index.stop() }
        try await waitUntil { !index.isRefreshing }
        #expect(index.allEntries.first?.name == "Initial")
        now = 30
        index.refreshForPopup()
        try await waitUntil { !index.isRefreshing }
        let cachedCalls = lock.withLock { iconCalls }
        #expect(cachedCalls == 1)
        try writeName("Renamed") // Same path; do not rely on Bundle's cached Info.plist.
        now = 60
        index.refreshForPopup()
        try await waitUntil { !index.isRefreshing }
        #expect(index.allEntries.first?.name == "Renamed")
        let (totalCalls, offMain) = lock.withLock { (iconCalls, iconsOffMain) }
        #expect(totalCalls == 2)
        #expect(offMain)
        try FileManager.default.removeItem(at: app)
        now = 90
        index.refreshForPopup()
        try await waitUntil { !index.isRefreshing }
        #expect(index.allEntries.isEmpty)
    }

    @Test func cachedEntriesIconsAndTargetedInvalidation() {
        var candidates = [AppIndexCandidate(path: "/unused/A.app", name: "Alpha"),
                          AppIndexCandidate(path: "/unused/B.app", name: "Beta")]
        var loads: [String] = []
        let builder = CachedAppIndexBuilder(discover: { candidates }, loadIcon: { path in
            loads.append(path)
            return IconFixture.icon() // Already-rasterized in-memory pixels only.
        })
        let first = builder.build(invalidation: .init())
        let second = builder.build(invalidation: .init())
        #expect(loads.count == 2)
        #expect(first[0].icon === second[0].icon)
        let third = builder.build(invalidation: .init(paths: ["/unused/A.app/Contents/Resources/Icon.icns"]))
        #expect(loads.count == 3)
        #expect(third[0].icon !== second[0].icon)
        #expect(third[1].icon === second[1].icon)
        candidates[1] = AppIndexCandidate(path: "/unused/B.app", name: "Renamed")
        _ = builder.build(invalidation: .init())
        #expect(loads.count == 4)
        candidates.removeFirst()
        #expect(builder.build(invalidation: .init()).count == 1)
        candidates.append(AppIndexCandidate(path: "/unused/A.app", name: "Alpha"))
        _ = builder.build(invalidation: .init())
        #expect(loads.count == 5) // Deleted entries were evicted, not cached forever.
        _ = builder.build(invalidation: .init(all: true))
        #expect(loads.count == 7)
    }

    @Test func failedIconPreparationIsRetriedOnNextScan() {
        var loads = 0
        let builder = CachedAppIndexBuilder(discover: { [.init(path: "/unused/A.app", name: "Alpha")] },
            loadIcon: { _ in loads += 1; return loads == 1 ? nil : IconFixture.icon() })
        #expect(builder.build(invalidation: .init()).first?.icon == nil)
        #expect(builder.build(invalidation: .init()).first?.icon != nil)
        _ = builder.build(invalidation: .init())
        #expect(loads == 2) // Recovery succeeded, so reuse that prepared snapshot.
    }

    @Test func revisionChangesAndBoundedInvalidation() {
        var candidate = AppIndexCandidate(path: "/unused/A.app", name: "Alpha")
        var loads = 0
        let builder = CachedAppIndexBuilder(discover: { [candidate] }, loadIcon: { _ in loads += 1; return nil })
        _ = builder.build(invalidation: .init())
        candidate.revision = [.init(modified: Date(timeIntervalSince1970: 123), size: 100, inode: 1)]
        _ = builder.build(invalidation: .init())
        #expect(loads == 2)
        var invalidation = AppIndexInvalidation()
        invalidation.merge(paths: (0..<300).map { "/unused/\($0).app" }, all: false)
        #expect(invalidation.all)
        #expect(invalidation.paths.isEmpty)
        #expect(AppIndexInvalidation(paths: ["/unused/"]).affects("/unused/A.app"))
        #expect(!AppIndexInvalidation(paths: ["/unused/A.app"]).affects("/unused/A.app-other"))
    }

    @Test func droppedEventsAndRootChangesRequestRecovery() {
        for flag in [kFSEventStreamEventFlagMustScanSubDirs, kFSEventStreamEventFlagUserDropped,
                     kFSEventStreamEventFlagKernelDropped, kFSEventStreamEventFlagEventIdsWrapped] {
            let dropped = FSEventsAppIndexWatcher.event(paths: ["/unused"], flags: UInt32(flag))
            #expect(dropped.invalidateAll)
            #expect(!dropped.restartWatcher)
        }
        let ordinary = FSEventsAppIndexWatcher.event(paths: ["/unused/A.app"], flags: UInt32(kFSEventStreamEventFlagItemCreated))
        #expect(!ordinary.invalidateAll)
        #expect(!ordinary.restartWatcher)
        let root = FSEventsAppIndexWatcher.event(paths: ["/unused"], flags: UInt32(kFSEventStreamEventFlagRootChanged))
        #expect(root.invalidateAll)
        #expect(root.restartWatcher)
        #expect(FSEventsAppIndexWatcher.event(paths: [], flags: 0).invalidateAll)
    }
}
