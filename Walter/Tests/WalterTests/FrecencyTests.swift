import Testing
@testable import Walter

@Suite("FrecencyTracker")
struct FrecencyTests {

    @Test func freshTrackerReturnsZero() {
        let tracker = FrecencyTracker()
        #expect(tracker.score(for: "/nonexistent/app") == 0)
    }

    @Test func scoreIncreasesWithLaunches() {
        let tracker = FrecencyTracker()
        tracker.recordLaunch(path: "/test/app")
        let s1 = tracker.score(for: "/test/app")
        tracker.recordLaunch(path: "/test/app")
        let s2 = tracker.score(for: "/test/app")
        #expect(s2 > s1)
    }

    @Test func differentAppsTrackedSeparately() {
        let tracker = FrecencyTracker()
        tracker.recordLaunch(path: "/app/a")
        #expect(tracker.score(for: "/app/a") > 0)
        #expect(tracker.score(for: "/app/b") == 0)
    }
}
