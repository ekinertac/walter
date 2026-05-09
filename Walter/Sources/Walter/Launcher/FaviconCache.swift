// FaviconCache.swift — On-disk + in-memory favicon cache for URL aliases
//
// User-defined aliases that point at a website (`y =
// "https://youtube.com/results?search_query={query}"`) used to render with
// a generic chain-link icon, which made parameterized aliases visually
// indistinguishable from each other. Showing the site's favicon lets the
// user spot "the YouTube one" or "the GitHub one" at a glance.
//
// We use DuckDuckGo's icon service rather than scraping each site's
// /favicon.ico ourselves: it returns a normalized 32×32 PNG-or-ICO and
// already handles the long tail of CDN-hosted, JavaScript-bound, or
// dimension-quirky favicons that `<link rel="icon">` introduces. URL
// shape is `https://icons.duckduckgo.com/ip3/<hostname>.ico`.
//
// Caching:
//   * Disk:   ~/.config/walter/.cache/favicons/<hostname>.png
//   * Memory: hostname → NSImage, populated on first hit and refreshed
//             whenever a prefetch completes.
//
// Lifecycle:
//   * ConfigManager.load() collects every URL alias hostname and calls
//     prefetch(hostnames:) so the first launcher search after a config
//     change already has the icons.
//   * LauncherEngine reads via image(for:) at result-build time. Cache
//     misses fall back to the system "link" SF Symbol, so a fresh install
//     never renders missing icons — it just upgrades them on the next
//     keystroke after the network request completes.

import AppKit

final class FaviconCache {

    static let shared = FaviconCache()

    private let cacheDir: URL
    private var memCache: [String: NSImage] = [:]
    private var inflight: Set<String> = []
    private let queue = DispatchQueue(label: "walter.favicon", qos: .utility)

    /// Provider URL template. Anything containing `{host}` is treated as a
    /// custom template; the shorthand strings expand to known services.
    /// Updated by ConfigManager on every load. Reassigning the template to
    /// a different value invalidates the on-disk cache so the user picks
    /// up higher-resolution icons without manually wiping files.
    var serviceTemplate: String = "https://www.google.com/s2/favicons?domain={host}&sz=128" {
        didSet {
            guard oldValue != serviceTemplate else { return }
            invalidateAll()
        }
    }

    private func invalidateAll() {
        memCache.removeAll()
        guard let files = try? FileManager.default.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: nil) else { return }
        for file in files where file.pathExtension == "png" {
            try? FileManager.default.removeItem(at: file)
        }
    }

    private init() {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/walter/.cache/favicons")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.cacheDir = dir
    }

    /// Resolves a `[search] favicon_service` config string into a URL
    /// template. Pass a known shorthand or a full template (passed through).
    static func template(for service: String) -> String {
        let trimmed = service.trimmingCharacters(in: .whitespaces)
        if trimmed.contains("{host}") { return trimmed }
        switch trimmed.lowercased() {
        case "duckduckgo", "ddg":
            return "https://icons.duckduckgo.com/ip3/{host}.ico"
        case "iconhorse", "icon.horse":
            return "https://icon.horse/icon/{host}"
        default:
            // Google S2 — defaults here cover empty / unknown values too.
            return "https://www.google.com/s2/favicons?domain={host}&sz=128"
        }
    }

    // MARK: - Public API

    /// Returns a cached favicon for the given hostname, loading it from
    /// disk on first request. Does not trigger a network fetch — that is
    /// the job of `prefetch(hostnames:)`. Returns nil for unknown hosts.
    func image(for hostname: String) -> NSImage? {
        if let cached = memCache[hostname] { return cached }
        let path = cacheDir.appendingPathComponent("\(hostname).png")
        guard FileManager.default.fileExists(atPath: path.path),
              let img = NSImage(contentsOf: path) else { return nil }
        memCache[hostname] = img
        return img
    }

    /// Kicks off background fetches for any host that isn't already cached
    /// or in flight. Safe to call from any thread; results land back in
    /// memCache on the main thread so subsequent renders see them.
    func prefetch(hostnames: [String]) {
        let unique = Set(hostnames)
        for host in unique {
            queue.async { [weak self] in
                self?.fetchIfNeeded(host: host)
            }
        }
    }

    /// Extracts the hostname from a URL alias template. The template may
    /// contain a literal `{query}` placeholder anywhere — even inside the
    /// host part of unusual setups — so we substitute a stub before parsing.
    static func hostname(for urlTemplate: String) -> String? {
        let resolved = urlTemplate.replacingOccurrences(of: "{query}", with: "x")
        guard let url = URL(string: resolved), let host = url.host else { return nil }
        return host.lowercased()
    }

    // MARK: - Network

    private func fetchIfNeeded(host: String) {
        if memCache[host] != nil { return }
        if inflight.contains(host) { return }

        let path = cacheDir.appendingPathComponent("\(host).png")
        if FileManager.default.fileExists(atPath: path.path) {
            // Already on disk — promote into mem cache on the main thread
            // so the next render sees it.
            if let img = NSImage(contentsOf: path) {
                DispatchQueue.main.async { [weak self] in
                    self?.memCache[host] = img
                }
            }
            return
        }

        inflight.insert(host)
        let urlString = serviceTemplate.replacingOccurrences(of: "{host}", with: host)
        guard let url = URL(string: urlString) else {
            inflight.remove(host)
            return
        }

        // URLSession dataTask gives us a real timeout + retries semantics
        // and doesn't block this serial queue while waiting for bytes.
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            guard let self = self else { return }
            self.queue.async { self.inflight.remove(host) }

            guard let data = data,
                  let img = NSImage(data: data),
                  img.size.width > 0 else { return }

            // Write the original bytes — DDG sends a small ICO/PNG that is
            // valid as-is. NSImage(contentsOf:) reads either format.
            try? data.write(to: path)

            DispatchQueue.main.async { [weak self] in
                self?.memCache[host] = img
            }
        }.resume()
    }
}
