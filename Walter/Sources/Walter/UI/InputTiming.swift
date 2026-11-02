import Foundation

/// Opt-in, main-thread-only input diagnostics. No keys, queries, result names,
/// paths, counters, or wall-clock timestamps enter the output. No log files,
/// preferences, timers, observers, or network activity are created here.
final class InputTiming {
    static let shared = InputTiming(
        enabled: ProcessInfo.processInfo.environment["WALTER_INPUT_TIMING"] == "1",
        clock: { ProcessInfo.processInfo.systemUptime },
        emit: { line in
            try? FileHandle.standardError.write(contentsOf: Data((line + "\n").utf8))
        })

    enum Phase: String, CaseIterable {
        case font, conversion, calculator, aliases, settings, apps, ranking
        case search, views
        case viewContent = "view-content"
        case viewPool = "view-pool"
        case viewClear = "view-clear"
        case viewDocument = "view-document"
        case viewImages = "view-images"
        case viewText = "view-text"
        case viewSelection = "view-selection"
        case viewScroll = "view-scroll"
        case colors, geometry, delegate, handler
    }

    final class Event {
        fileprivate let start: TimeInterval
        fileprivate let age: TimeInterval?
        fileprivate var durations: [Phase: TimeInterval] = [:]
        fileprivate init(start: TimeInterval, age: TimeInterval?) {
            self.start = start
            self.age = age
        }
    }

    private let enabled: Bool
    private let clock: () -> TimeInterval
    private let emit: (String) -> Void
    private var active: Event?
    private var pendingWindowUpdate: Event?

    // Tests inject a clock and an in-memory sink; they never write stderr or
    // construct an application/window. Disabled mode does not even read a clock.
    init(enabled: Bool, clock: @escaping () -> TimeInterval, emit: @escaping (String) -> Void) {
        self.enabled = enabled
        self.clock = clock
        self.emit = emit
    }

    func beginKeyEvent(timestamp: TimeInterval) -> Event? {
        guard enabled, Thread.isMainThread, active == nil else { return nil }
        let start = clock()
        // NSEvent.timestamp and systemUptime share the uptime time base. Omit
        // invalid/future timestamps rather than emitting misleading negative ages.
        let age = timestamp.isFinite && timestamp >= 0 && timestamp <= start ? start - timestamp : nil
        let event = Event(start: start, age: age)
        active = event
        pendingWindowUpdate = nil // Only the latest event awaits a window update.
        return event
    }

    func measure<T>(_ phase: Phase, _ work: () throws -> T) rethrows -> T {
        guard enabled, Thread.isMainThread, let event = active else { return try work() }
        let start = clock()
        defer { event.durations[phase, default: 0] += max(0, clock() - start) }
        return try work()
    }

    func endKeyEvent(_ event: Event?) {
        guard enabled, Thread.isMainThread, let event, event === active else { return }
        event.durations[.handler] = max(0, clock() - event.start)
        active = nil
        pendingWindowUpdate = event
        var fields: [String] = []
        if let age = event.age { fields.append("event-age=\(Self.ms(age))") }
        for phase in Phase.allCases {
            if let duration = event.durations[phase] { fields.append("\(phase.rawValue)=\(Self.ms(duration))") }
        }
        // One write after timing the handler, not a write inside every phase.
        emit("[Walter input] " + fields.joined(separator: " "))
    }

    func windowUpdate(_ work: () -> Void) {
        guard enabled, Thread.isMainThread, active == nil, let event = pendingWindowUpdate else { work(); return }
        pendingWindowUpdate = nil
        let start = clock()
        work()
        let end = clock()
        emit("[Walter input] next-window-update-start=\(Self.ms(max(0, start - event.start))) " +
             "window-update-work=\(Self.ms(max(0, end - start)))")
        // NSWindow.update is a CPU-side milestone, NOT proof that pixels have
        // reached the screen. Core Animation/WindowServer presentation is later.
    }

    private static func ms(_ seconds: TimeInterval) -> String {
        // Integer formatting avoids warming NumberFormatter/ICU in a timing log.
        let micros = Int((seconds * 1_000_000).rounded())
        let fraction = String(micros % 1000)
        return "\(micros / 1000)." + String(repeating: "0", count: 3 - fraction.count) + fraction + "ms"
    }
}
