// Computed answers lead, ordinary fuzzy-ranked results follow, web is fallback.
import AppKit

struct SearchResult {
    let title: String
    let subtitle: String
    let icon: PreparedIcon?
    let action: ResultAction
}

enum ResultAction {
    case openApp(String)
    case copy(String)
    case url(String)
    case settings(String)
    case enterThemePicker
    case applyTheme(String)
}

final class LauncherEngine {
    private let calculator: Calculator
    private let converter: Converter
    private let prefPanes = PrefPaneIndex()
    private let config: ConfigManager
    private let entries: () -> [AppEntry]
    private let apps: AllowedApps
    private let openURL: (URL) -> Void
    private struct SymbolLookup {
        let load: (String, String) -> PreparedIcon?
        func image(name: String, description: String) -> PreparedIcon? { load(name, description) }
    }
    private let symbols: SymbolLookup

    // No scanning, watching, or persistence in this constructor. The application
    // owns its index separately; tests provide entries and mock OS handoffs.
    init(config: ConfigManager, entries: @escaping () -> [AppEntry],
         apps: AllowedApps = AllowedApps(), locale: Locale = .current,
         openURL: @escaping (URL) -> Void = { NSWorkspace.shared.open($0) },
         symbolLoader: @escaping (String, String) -> PreparedIcon? = { _, _ in nil }) {
        self.config = config
        self.calculator = Calculator(locale: locale)
        self.converter = Converter(locale: locale)
        self.entries = entries
        self.apps = apps
        self.openURL = openURL
        // Lookup only: default is empty for isolated tests. The app injects its
        // worker-prepared symbol snapshot. Never negatively cache startup misses.
        self.symbols = SymbolLookup(load: symbolLoader)
    }

    func search(query: String) -> [SearchResult] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        var answers: [SearchResult] = []
        var scored: [(SearchResult, Int)] = []
        let conversions = InputTiming.shared.measure(.conversion) { converter.convert(query: q) }
        answers += conversions.map {
            SearchResult(title: $0.title, subtitle: "\($0.subtitle) — Enter to copy",
                         icon: symbols.image(name: "arrow.left.arrow.right", description: "Convert"),
                         action: .copy($0.copyValue))
        }
        if conversions.isEmpty, let answer = InputTiming.shared.measure(.calculator, { calculator.evaluate(query: q) }) {
            answers.append(SearchResult(title: answer.answer, subtitle: "\(answer.expression) — Enter to copy",
                icon: symbols.image(name: "equal.circle", description: "Calculator"),
                action: .copy(answer.answer)))
        }
        if let space = q.firstIndex(of: " ") {
            let key = String(q[..<space]).lowercased()
            let rest = String(q[q.index(after: space)...]).trimmingCharacters(in: .whitespaces)
            if !rest.isEmpty, let value = config.aliases[key], value.contains("{query}"),
               BrowserURL.parse(value.replacingOccurrences(of: "{query}", with: "x")) != nil {
                let encoded = BrowserURL.encodeQuery(rest)
                let target = value.replacingOccurrences(of: "{query}", with: encoded)
                if BrowserURL.parse(target) != nil {
                    answers.append(aliasResult(name: "\(config.aliasNames[key] ?? key) → \(rest)", value: target))
                    return answers + [webFallback(q)]
                }
            }
        }
        InputTiming.shared.measure(.aliases) {
            for (key, value) in config.aliases where !value.contains("{query}") {
                guard ConfigManager.isAllowedAliasValue(value, appRoot: apps.root.path) else { continue }
                let match = fuzzyMatch(query: q, target: key)
                if match.matched {
                    scored.append((aliasResult(name: config.aliasNames[key] ?? key, value: value), match.score))
                }
            }
        }
        let themeMatch = fuzzyMatch(query: q, target: "Change Theme")
        if themeMatch.matched {
            scored.append((SearchResult(title: "Change Theme", subtitle: "Browse built-in and user themes",
                icon: symbols.image(name: "paintpalette", description: "Theme"),
                action: .enterThemePicker), themeMatch.score))
        }
        InputTiming.shared.measure(.settings) {
            for item in prefPanes.search(query: q) {
                scored.append((SearchResult(title: item.pane.name, subtitle: "System Settings",
                    icon: symbols.image(name: item.pane.iconName, description: item.pane.name),
                    action: .settings(item.pane.url)), item.score))
            }
        }
        InputTiming.shared.measure(.apps) {
            let excluded = Set(config.search.excludedApps.map { $0.lowercased() })
            for entry in entries() where !excluded.contains(entry.nameLower) {
                let match = fuzzyMatch(query: q, target: entry.name)
                if match.matched {
                    scored.append((SearchResult(title: entry.name,
                        subtitle: config.search.showPath ? entry.path : "", icon: entry.icon,
                        action: .openApp(entry.path)), match.score))
                }
            }
        }
        InputTiming.shared.measure(.ranking) {
            scored.sort {
                if $0.1 != $1.1 { return $0.1 > $1.1 }
                return $0.0.title.localizedCaseInsensitiveCompare($1.0.title) == .orderedAscending
            }
        }
        return answers + scored.prefix(25).map { $0.0 } + [webFallback(q)]
    }

    private func aliasResult(name: String, value: String) -> SearchResult {
        let isURL = BrowserURL.parse(value) != nil
        return SearchResult(title: name, subtitle: value,
            icon: symbols.image(name: isURL ? "link" : "app", description: "Alias"),
            action: isURL ? .url(value) : .openApp(value))
    }

    private func webFallback(_ query: String) -> SearchResult {
        let encoded = BrowserURL.encodeQuery(query)
        let engine = config.search.webSearch
        let target: String
        let name: String
        if engine.contains("{query}"), BrowserURL.parse(engine.replacingOccurrences(of: "{query}", with: "x")) != nil {
            target = engine.replacingOccurrences(of: "{query}", with: encoded)
            name = URL(string: target)?.host ?? "Web"
        } else {
            switch engine.lowercased() {
            case "duckduckgo", "ddg": name = "DuckDuckGo"; target = "https://duckduckgo.com/?q=\(encoded)"
            case "bing": name = "Bing"; target = "https://www.bing.com/search?q=\(encoded)"
            default: name = "Google"; target = "https://www.google.com/search?q=\(encoded)"
            }
        }
        return SearchResult(title: "Search \(name) for \"\(query)\"", subtitle: "Open in default browser",
            icon: symbols.image(name: "magnifyingglass.circle", description: "Web search"),
            action: .url(target))
    }

    func launch(result: SearchResult) {
        switch result.action {
        case .openApp(let path): apps.launch(path: path, open: openURL)
        case .url(let value):
            if let url = BrowserURL.parse(value) { openURL(url) }
        case .settings(let value):
            // Only locally bundled pane links, never arbitrary URL schemes.
            if prefPanes.panes.contains(where: { $0.url == value }), let url = URL(string: value) { openURL(url) }
        case .copy(let value):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(value, forType: .string)
        case .enterThemePicker, .applyTheme: break
        }
    }

    func themeResults(filter: String) -> [SearchResult] {
        let q = filter.trimmingCharacters(in: .whitespaces)
        return config.allThemes.keys.sorted().compactMap { name in
            guard q.isEmpty || fuzzyMatch(query: q, target: name).matched else { return nil }
            let title = name.split(separator: "-").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
            let group = config.userThemes[name] == nil ? "Built-in" : "Custom"
            return SearchResult(title: title, subtitle: group + (config.theme.name == name ? " — current" : ""),
                icon: symbols.image(name: "paintpalette", description: "Theme"), action: .applyTheme(name))
        }
    }

    func applyTheme(name: String) {
        config.selectTheme(name)
    }
}

/// Local URL construction/validation only; never resolves DNS or fetches data.
enum BrowserURL {
    static func parse(_ value: String) -> URL? {
        guard let url = URL(string: value), ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host, !host.isEmpty else { return nil }
        return url
    }

    static func encodeQuery(_ query: String) -> String {
        // Encode separators too, so typed '&' cannot inject another parameter.
        query.addingPercentEncoding(withAllowedCharacters: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))) ?? ""
    }
}
