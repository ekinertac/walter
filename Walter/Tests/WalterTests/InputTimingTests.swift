import Foundation
import Testing
@testable import Walter

@Suite("Opt-in input timing (fake clock and in-memory output)")
@MainActor
struct InputTimingTests {
    @Test func disabledRunsWorkWithoutClocksOrOutput() {
        var clockReads = 0
        var lines: [String] = []
        var work = 0
        let timing = InputTiming(enabled: false, clock: { clockReads += 1; return 10 }, emit: { lines.append($0) })
        let event = timing.beginKeyEvent(timestamp: 9)
        let value = timing.measure(.search) { work += 1; return 42 }
        timing.endKeyEvent(event)
        for phase in InputTiming.Phase.allCases { timing.measure(phase) {} }
        timing.windowUpdate { work += 1 }
        #expect(event == nil)
        #expect(value == 42)
        #expect(work == 2)
        #expect(clockReads == 0)
        #expect(lines.isEmpty)
    }

    @Test func groupedInclusiveDurationsAndNextWindowUpdate() {
        var now: TimeInterval = 100
        var lines: [String] = []
        let timing = InputTiming(enabled: true, clock: { now }, emit: { lines.append($0) })
        let event = timing.beginKeyEvent(timestamp: 99.995)
        timing.measure(.delegate) {
            timing.measure(.font) { now += 0.002 }
            timing.measure(.search) { now += 0.003 }
            now += 0.001
        }
        timing.endKeyEvent(event)
        #expect(lines == ["[Walter input] event-age=5.000ms font=2.000ms search=3.000ms delegate=6.000ms handler=6.000ms"])
        now += 0.004
        timing.windowUpdate { now += 0.002 }
        #expect(lines.last == "[Walter input] next-window-update-start=10.000ms window-update-work=2.000ms")
        timing.windowUpdate { now += 1 } // Runs normally, without logging repeatedly.
        #expect(lines.count == 2)
    }

    @Test func repeatedViewSubphasesAggregateWithoutDuplicatingOutput() {
        var now: TimeInterval = 10
        var lines: [String] = []
        let timing = InputTiming(enabled: true, clock: { now }, emit: { lines.append($0) })
        let event = timing.beginKeyEvent(timestamp: now)
        timing.measure(.views) {
            timing.measure(.viewContent) {
                timing.measure(.viewPool) { timing.measure(.viewClear) { now += 0.001 } }
                timing.measure(.viewDocument) { now += 0.002 }
                for _ in 0..<2 {
                    timing.measure(.viewImages) { now += 0.003 }
                    timing.measure(.viewText) { now += 0.004 }
                }
            }
            timing.measure(.viewSelection) { now += 0.005 }
            timing.measure(.viewScroll) { now += 0.006 }
        }
        timing.endKeyEvent(event)
        #expect(lines == ["[Walter input] event-age=0.000ms views=28.000ms view-content=17.000ms view-pool=1.000ms view-clear=1.000ms view-document=2.000ms view-images=6.000ms view-text=8.000ms view-selection=5.000ms view-scroll=6.000ms handler=28.000ms"])
    }

    @Test func throwingWorkKeepsItsErrorAndItsTiming() {
        enum FixtureError: Error { case expected }
        var now: TimeInterval = 10
        var lines: [String] = []
        let timing = InputTiming(enabled: true, clock: { now }, emit: { lines.append($0) })
        let event = timing.beginKeyEvent(timestamp: now)
        do {
            try timing.measure(.search) { now += 0.007; throw FixtureError.expected }
            Issue.record("The diagnostic wrapper swallowed an error")
        } catch FixtureError.expected {} catch { Issue.record("Unexpected error: \(error)") }
        timing.endKeyEvent(event)
        #expect(lines.count == 1)
        #expect(lines[0].contains("search=7.000ms"))
        #expect(lines[0].contains("handler=7.000ms"))
        #expect(!lines[0].contains("expected"))
    }

    @Test func onlyLatestEventAwaitsWindowUpdateAndInvalidAgesAreOmitted() {
        var now: TimeInterval = 0
        var lines: [String] = []
        let timing = InputTiming(enabled: true, clock: { now }, emit: { lines.append($0) })
        timing.endKeyEvent(timing.beginKeyEvent(timestamp: .nan))
        now = 2
        timing.endKeyEvent(timing.beginKeyEvent(timestamp: 3))
        #expect(lines.count == 2)
        #expect(lines.allSatisfy { !$0.contains("event-age") })
        now += 0.010
        timing.windowUpdate { now += 0.002 }
        #expect(lines.count == 3)
        #expect(lines.last == "[Walter input] next-window-update-start=10.000ms window-update-work=2.000ms")
    }

    @Test func nestedEventsCannotEndOrReplaceOuterMeasurement() {
        var now: TimeInterval = 1
        var lines: [String] = []
        let timing = InputTiming(enabled: true, clock: { now }, emit: { lines.append($0) })
        let outer = timing.beginKeyEvent(timestamp: now)
        let nested = timing.beginKeyEvent(timestamp: now)
        #expect(nested == nil)
        timing.endKeyEvent(nested)
        timing.measure(.views) { now += 0.003 }
        timing.windowUpdate { now += 0.001 } // Synchronous update is part of handler time.
        #expect(lines.isEmpty)
        timing.endKeyEvent(outer)
        #expect(lines.count == 1)
        #expect(lines[0].contains("views=3.000ms"))
        #expect(lines[0].contains("handler=4.000ms"))
    }
}
