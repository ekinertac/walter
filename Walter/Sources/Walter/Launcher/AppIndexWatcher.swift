import Foundation
import CoreServices

struct AppIndexEvent {
    var paths: [String] = []
    var invalidateAll = false
    var restartWatcher = false
}

protocol AppIndexWatching: AnyObject {
    /// Start before the initial scan. Events are delivered on main; tests inject
    /// a fake and never register filesystem watchers or inspect system app roots.
    func start(onChange: @escaping (AppIndexEvent) -> Void) -> Bool
    func stop()
}

final class FSEventsAppIndexWatcher: AppIndexWatching {
    let roots: [URL]
    private var stream: FSEventStreamRef?
    private var onChange: ((AppIndexEvent) -> Void)?

    init(roots: [URL]) { self.roots = roots }
    deinit { stop() }

    func start(onChange: @escaping (AppIndexEvent) -> Void) -> Bool {
        stop()
        self.onChange = onChange
        var context = FSEventStreamContext(version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        guard let stream = FSEventStreamCreate(nil, { _, info, count, paths, flags, _ in
            guard let info else { return }
            let watcher = Unmanaged<FSEventsAppIndexWatcher>.fromOpaque(info).takeUnretainedValue()
            let paths = Unmanaged<CFArray>.fromOpaque(paths).takeUnretainedValue() as NSArray
            // Large batches need a full invalidation, not a huge main-thread
            // allocation of individual paths. Still inspect all recovery flags.
            let eventPaths = count > 256 ? [] : paths.compactMap { $0 as? String }
            let combined = UnsafeBufferPointer(start: flags, count: count).reduce(UInt32(0), |)
            watcher.onChange?(FSEventsAppIndexWatcher.event(paths: eventPaths, flags: combined))
        }, &context, roots.map(\.path) as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 1,
            UInt32(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagWatchRoot)) else {
            self.onChange = nil
            return false
        }
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, .main)
        guard FSEventStreamStart(stream) else { stop(); return false }
        return true
    }

    // Pure flag decoding is testable without creating a real event stream.
    static func event(paths: [String], flags: UInt32) -> AppIndexEvent {
        let recovery = UInt32(kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagUserDropped |
            kFSEventStreamEventFlagKernelDropped | kFSEventStreamEventFlagEventIdsWrapped)
        let restart = flags & UInt32(kFSEventStreamEventFlagRootChanged | kFSEventStreamEventFlagUnmount) != 0
        return AppIndexEvent(paths: paths, invalidateAll: paths.isEmpty || restart || flags & recovery != 0,
                             restartWatcher: restart)
    }

    func stop() {
        onChange = nil
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }
}
