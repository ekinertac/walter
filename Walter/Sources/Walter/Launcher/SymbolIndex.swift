import AppKit

/// Application-lifetime built-ins, prepared once on a utility worker. Views and
/// engines only perform read-only lookups; startup misses are not cached by an
/// engine, so a later query can see publication without rebuilding the panel.
final class SymbolIndex {
    struct Request {
        let name: String
        let description: String
    }

    static var requests: [Request] {
        var result = [
            Request(name: "arrow.left.arrow.right", description: "Convert"),
            Request(name: "equal.circle", description: "Calculator"),
            Request(name: "paintpalette", description: "Theme"),
            Request(name: "link", description: "Alias"),
            Request(name: "app", description: "Alias"),
            Request(name: "magnifyingglass.circle", description: "Web search")
        ]
        result += PrefPaneIndex().panes.map { Request(name: $0.iconName, description: $0.name) }
        return result
    }

    private var cache: SymbolCache<PreparedIcon>?
    private(set) var isReady = false
    private var stopped = false

    init(requests: [Request] = SymbolIndex.requests,
         load: @escaping (String, String) -> PreparedIcon? = { name, description in
             guard let source = NSImage(systemSymbolName: name, accessibilityDescription: description) else { return nil }
             return PreparedIcon.prepare(source)
         }, worker: DispatchQueue = DispatchQueue(label: "walter.symbol-preparation", qos: .utility),
         onChange: @escaping () -> Void = {}) {
        dispatchPrecondition(condition: .onQueue(.main))
        worker.async { [weak self] in
            let built = SymbolCache<PreparedIcon>(load: load)
            for request in requests {
                autoreleasepool { _ = built.image(name: request.name, description: request.description) }
            }
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.stopped else { return }
                self.cache = built
                self.isReady = true
                onChange()
            }
        }
    }

    func image(name: String, description: String) -> PreparedIcon? {
        dispatchPrecondition(condition: .onQueue(.main))
        return cache?.cachedImage(name: name, description: description)
    }

    /// Suppress publication/callbacks. An already running finite preparation
    /// finishes on its worker; no watcher, timer, service, or subsequent work.
    func stop() {
        dispatchPrecondition(condition: .onQueue(.main))
        stopped = true
        cache = nil
    }
}
