import Foundation
import Testing
@testable import Walter

@Suite("Background built-in icon snapshots (injected loader, no system assets)")
@MainActor
struct SymbolIndexTests {
    private func waitUntil(_ predicate: () -> Bool) async throws {
        for _ in 0..<150 {
            if predicate() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        try #require(predicate(), "Timed out waiting for finite mocked symbol preparation")
    }

    @Test func preparesOnceOffMainAndPublishesReadOnlyLookups() async throws {
        let lock = NSLock()
        var calls = 0
        var offMain = true
        var changes = 0
        let icon = IconFixture.icon()
        let request = SymbolIndex.Request(name: "fixture", description: "Fixture")
        let index = SymbolIndex(requests: [request, request, .init(name: "missing", description: "Missing")],
            load: { name, _ in
                lock.withLock { calls += 1; offMain = offMain && !Thread.isMainThread }
                return name == "missing" ? nil : icon
            }, onChange: { changes += 1; #expect(Thread.isMainThread) })
        defer { index.stop() }
        #expect(index.image(name: "fixture", description: "Fixture") == nil)
        try await waitUntil { index.isReady }
        #expect(index.image(name: "fixture", description: "Fixture") === icon)
        for _ in 0..<10 {
            #expect(index.image(name: "missing", description: "Missing") == nil)
            #expect(index.image(name: "not-prepared", description: "Other") == nil)
        }
        let recorded = lock.withLock { (calls, offMain) }
        #expect(recorded.0 == 2) // Duplicate pair deduplicated; misses never load on main.
        #expect(recorded.1)
        #expect(changes == 1)
    }

    @Test func stopSuppressesPublicationAndCallbacks() async {
        let worker = DispatchQueue(label: "walter.test-symbols")
        var changes = 0
        let index = SymbolIndex(requests: [.init(name: "fixture", description: "Fixture")],
            load: { _, _ in IconFixture.icon() }, worker: worker, onChange: { changes += 1 })
        index.stop() // Main publication cannot run before this synchronous stop.
        // Drain the finite worker AND its queued main publication before checking.
        await withCheckedContinuation { continuation in
            worker.async { DispatchQueue.main.async { continuation.resume() } }
        }
        #expect(!index.isReady)
        #expect(index.image(name: "fixture", description: "Fixture") == nil)
        #expect(changes == 0)
    }

    @Test func catalogCoversBuiltInsAndEverySettingsPane() {
        let requests = SymbolIndex.requests
        for (name, description) in [("arrow.left.arrow.right", "Convert"), ("equal.circle", "Calculator"),
                                    ("paintpalette", "Theme"), ("link", "Alias"), ("app", "Alias"),
                                    ("magnifyingglass.circle", "Web search")] {
            #expect(requests.contains { $0.name == name && $0.description == description })
        }
        for pane in PrefPaneIndex().panes {
            #expect(requests.contains { $0.name == pane.iconName && $0.description == pane.name })
        }
    }
}
