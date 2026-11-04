// Worker-only snapshot preparation. Nothing here updates AppKit views.
import AppKit

struct AppIndexInvalidation {
    var all = false
    var paths: Set<String> = []

    mutating func merge(paths: [String], all: Bool) {
        // Bound both retained paths and work per merge during event storms.
        self.all = self.all || all || paths.count > 256
        if !self.all { self.paths.formUnion(paths) }
        if self.paths.count > 256 { self.all = true }
        if self.all { self.paths.removeAll() }
    }

    func affects(_ path: String) -> Bool {
        all || paths.contains { changed in
            let changed = changed.trimmingTrailingSlash
            return changed == "/" || changed == path || path.hasPrefix(changed + "/") || changed.hasPrefix(path + "/")
        }
    }
}

private extension String {
    var trimmingTrailingSlash: String {
        var value = self
        while value.count > 1 && value.hasSuffix("/") { value.removeLast() }
        return value
    }
}

protocol AppIndexBuilding: AnyObject {
    /// Called serially on a worker queue. Returned entries/images are immutable
    /// after publication; the main thread only receives the finished array.
    func build(invalidation: AppIndexInvalidation) -> [AppEntry]
}

struct AppIndexCandidate: Equatable {
    struct Stamp: Equatable {
        let modified: Date?
        let size: UInt64?
        let inode: UInt64?
    }
    let path: String
    let name: String
    var revision: [Stamp] = []
}

final class CachedAppIndexBuilder: AppIndexBuilding {
    private let discover: () -> [AppIndexCandidate]
    private let loadIcon: (String) -> PreparedIcon?
    private var cache: [String: (candidate: AppIndexCandidate, entry: AppEntry)] = [:]

    init(discover: @escaping () -> [AppIndexCandidate], loadIcon: @escaping (String) -> PreparedIcon?) {
        self.discover = discover
        self.loadIcon = loadIcon
    }

    convenience init(policy: AllowedApps, loadIcon: @escaping (String) -> PreparedIcon? = { path in
        // Both acquisition AND raster preparation stay on the serial worker.
        PreparedIcon.prepare(NSWorkspace.shared.icon(forFile: path))
    }) {
        self.init(discover: {
            policy.discover().compactMap { url in
                guard let metadata = policy.metadata(for: url.path) else { return nil }
                let info = metadata.info
                let localized = Bundle(url: url)?.localizedInfoDictionary
                let name = (localized?["CFBundleDisplayName"] as? String)
                    ?? (info["CFBundleDisplayName"] as? String)
                    ?? (localized?["CFBundleName"] as? String)
                    ?? (info["CFBundleName"] as? String)
                    ?? url.deletingPathExtension().lastPathComponent
                // These cheap stamps also catch installs/replacements during a
                // popup safety-net scan. FSEvents explicitly invalidates entries
                // for deeper resource changes, even if these stamps are equal.
                let paths = [url, url.appendingPathComponent("Contents/Info.plist"),
                             url.appendingPathComponent("Contents/Resources")]
                let revision = paths.map { path -> AppIndexCandidate.Stamp in
                    let attrs = try? FileManager.default.attributesOfItem(atPath: path.path)
                    return .init(modified: attrs?[.modificationDate] as? Date,
                                 size: (attrs?[.size] as? NSNumber)?.uint64Value,
                                 inode: (attrs?[.systemFileNumber] as? NSNumber)?.uint64Value)
                }
                return AppIndexCandidate(path: url.path, name: name, revision: revision)
            }
        }, loadIcon: loadIcon)
    }

    func build(invalidation: AppIndexInvalidation) -> [AppEntry] {
        var next: [String: (candidate: AppIndexCandidate, entry: AppEntry)] = [:]
        for candidate in discover() {
            if let cached = cache[candidate.path], cached.candidate == candidate,
               cached.entry.icon != nil, !invalidation.affects(candidate.path) {
                next[candidate.path] = cached
            } else {
                let icon = autoreleasepool { loadIcon(candidate.path) }
                next[candidate.path] = (candidate, AppEntry(name: candidate.name, path: candidate.path,
                    nameLower: candidate.name.lowercased(), icon: icon))
            }
        }
        cache = next // Drop removed apps; no ever-growing or on-disk cache.
        return next.values.map { $0.entry }.sorted {
            let comparison = $0.name.localizedCaseInsensitiveCompare($1.name)
            return comparison == .orderedSame ? $0.path < $1.path : comparison == .orderedAscending
        }
    }
}
