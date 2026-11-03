// One policy for discovery, aliases, and activation. Tests inject local roots.
import AppKit

struct AllowedApps {
    static let defaultRootPaths = ["/Applications", "/System/Applications"]
    let roots: [URL]

    init(roots: [URL] = AllowedApps.defaultRootPaths.map { URL(fileURLWithPath: $0, isDirectory: true) }) {
        self.roots = roots.map { $0.standardizedFileURL }
    }

    init(root: URL) { self.init(roots: [root]) }

    func validatedURL(for path: String) -> URL? { metadata(for: path)?.url }

    func metadata(for path: String) -> (url: URL, info: NSDictionary)? {
        for root in roots {
            if let metadata = AllowedAppRoot(root: root).metadata(for: path) { return metadata }
        }
        return nil
    }

    func discover() -> [URL] {
        let paths = Set(roots.flatMap { AllowedAppRoot(root: $0).discover().map(\.path) })
        return paths.sorted().map { URL(fileURLWithPath: $0) }
    }

    /// Revalidate immediately before OS handoff, not only when indexing.
    @discardableResult
    func launch(path: String, open: (URL) -> Void = { NSWorkspace.shared.open($0) }) -> Bool {
        guard let url = validatedURL(for: path) else { return false }
        open(url)
        return true
    }
}

/// A path must stay within its originating root, including metadata and every
/// symlink hop. Adding a root never permits traversal through an outside tree.
private struct AllowedAppRoot {
    let root: URL

    private func isInside(_ url: URL) -> Bool {
        url.path.hasPrefix(root.path + "/")
    }

    /// Resolve links one component at a time. Reject an escaping destination
    /// before probing it (it could name a network-backed volume). Never traverse
    /// an outside tree just to learn that the final path is outside the root.
    private func resolveInsideRoot(_ url: URL) -> URL? {
        func normalize(_ path: String) -> String {
            var parts: [String] = []
            for part in path.split(separator: "/") {
                if part == "." { continue }
                if part == ".." { if !parts.isEmpty { parts.removeLast() } }
                else { parts.append(String(part)) }
            }
            return "/" + parts.joined(separator: "/")
        }
        let initial = normalize(url.path)
        guard initial == root.path || initial.hasPrefix(root.path + "/"),
              (try? FileManager.default.destinationOfSymbolicLink(atPath: root.path)) == nil else { return nil }
        var remaining = Array(initial.dropFirst(root.path.count).split(separator: "/").map(String.init))
        var current = root.path
        var hops = 0
        while !remaining.isEmpty {
            let component = remaining.removeFirst()
            let candidate = current + "/" + component
            if let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: candidate) {
                hops += 1
                guard hops <= 64 else { return nil }
                let target = normalize(destination.hasPrefix("/") ? destination : current + "/" + destination)
                guard target == root.path || target.hasPrefix(root.path + "/") else { return nil }
                remaining = target.dropFirst(root.path.count).split(separator: "/").map(String.init) + remaining
                current = root.path
            } else { current = candidate }
        }
        return URL(fileURLWithPath: current)
    }

    /// Ordinary subfolders are allowed. Bundles are opaque leaves: an app
    /// embedded inside another app/package is never a launcher target.
    func validatedURL(for path: String) -> URL? { metadata(for: path)?.url }

    /// Validated metadata for worker-side indexing, without Bundle's persistent
    /// Info.plist cache (an installed app can be replaced at the same path).
    func metadata(for path: String) -> (url: URL, info: NSDictionary)? {
        let lexical = URL(fileURLWithPath: path).standardizedFileURL
        guard isInside(lexical), let resolved = resolveInsideRoot(lexical), isInside(resolved),
              lexical.pathExtension.lowercased() == "app",
              resolved.pathExtension.lowercased() == "app",
              !hasPackageAncestor(lexical), !hasPackageAncestor(resolved),
              (try? resolved.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true,
              let metadata = resolveInsideRoot(resolved.appendingPathComponent("Contents/Info.plist")),
              let info = NSDictionary(contentsOf: metadata),
              info["CFBundlePackageType"] as? String == "APPL" else { return nil }
        return (resolved, info)
    }

    private func hasPackageAncestor(_ url: URL) -> Bool {
        var parent = url.deletingLastPathComponent()
        while isInside(parent) {
            if parent.pathExtension.lowercased() == "app" ||
                (try? parent.resourceValues(forKeys: [.isPackageKey]))?.isPackage == true {
                return true
            }
            parent.deleteLastPathComponent()
        }
        return false
    }

    func discover() -> [URL] {
        var visited = Set<String>()
        var found = Set<String>()
        func walk(_ directory: URL) {
            guard let resolved = resolveInsideRoot(directory),
                  resolved.path == root.path || isInside(resolved),
                  visited.insert(resolved.path).inserted else { return }
            guard let children = try? FileManager.default.contentsOfDirectory(
                at: resolved, includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { return }
            for entry in children {
                // Directory enumeration may return a different spelling of a
                // local root (e.g. /private/tmp vs /tmp in isolated fixtures).
                let child = entry.standardizedFileURL
                if child.pathExtension.lowercased() == "app" {
                    if let allowed = validatedURL(for: child.path) { found.insert(allowed.path) }
                    continue
                }
                guard let target = resolveInsideRoot(child), isInside(target), !hasPackageAncestor(target),
                      let values = try? target.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey]),
                      values.isDirectory == true, values.isPackage != true else { continue }
                walk(target)
            }
        }
        walk(root)
        return found.sorted().map { URL(fileURLWithPath: $0) }
    }
}
