// LauncherEngine.swift — Core search and launch logic
//
// Result layout:
//   1. Calculator / converter answers — pinned to the top because they
//      are computed answers, not search results, and there is nothing
//      meaningful to score them against.
//   2. A unified pool of fuzzy-scored results — apps, System Settings
//      panes, aliases, and the "Change Theme" action all
//      compete in one ranked list using ordinary fuzzy matching.
//   3. Web search fallback — always pinned to the bottom so the user can
//      always escape to a web query.
//
// Called by: LauncherPanelController on every keystroke.

import AppKit

struct SearchResult {
    let title: String
    let subtitle: String
    let icon: NSImage?
    let action: ResultAction
}

enum ResultAction {
    case openApp(String)
    case copy(String)
    case url(String)
    case settings(String)
    case enterThemePicker          // switches UI to theme browsing mode
    case applyTheme(String)        // applies a theme by name and writes to config
}

class LauncherEngine {

    private let appIndex: AppIndex
    private let apps = AllowedApps()
    private let calculator = Calculator()
    private let converter = Converter()
    private let prefPanes = PrefPaneIndex()
    private weak var config: ConfigManager?

    init(config: ConfigManager, onIndexChanged: @escaping () -> Void = {}) {
        self.config = config
        appIndex = AppIndex(onChange: onIndexChanged)
    }

    /// Forwards a refresh request to the underlying app index. The
    /// panel controller calls this on every show so a freshly-installed
    /// app appears immediately even when FSEvents missed the install.
    func refreshIndexes() {
        appIndex.refresh()
    }

    func search(query: String) -> [SearchResult] {
        let q = query.trimmingCharacters(in: .whitespaces)
        if q.isEmpty { return [] }

        var pinnedTop: [SearchResult] = []
        var scored: [(result: SearchResult, score: Double)] = []

        // ----- Pinned top: calculator + converter answers ----------------
        // Computed answers, not searchable items — there is no fuzzy score
        // to compare them against, so they always lead the list.

        let conversions = converter.convert(query: q)
        if !conversions.isEmpty {
            let icon = NSImage(systemSymbolName: "arrow.left.arrow.right", accessibilityDescription: "Convert")
            pinnedTop += conversions.map { conv in
                SearchResult(
                    title: conv.title,
                    subtitle: "\(conv.subtitle) — Enter to copy",
                    icon: icon,
                    action: .copy(conv.copyValue)
                )
            }
        }
        // Skip the calculator if a conversion already matched, otherwise
        // "1920x1080" produces both a multiplication and a resolution conv.
        if conversions.isEmpty, let calc = calculator.evaluate(query: q) {
            let icon = NSImage(systemSymbolName: "equal.circle", accessibilityDescription: "Calculator")
            pinnedTop.append(SearchResult(
                title: calc.answer,
                subtitle: "\(calc.expression) — Enter to copy",
                icon: icon,
                action: .copy(calc.answer)
            ))
        }

        // ----- Scored pool: apps, panes, aliases, theme entry --
        // All searchable items live in a single ranked list keyed by the
        // fuzzy score against the query, without launch tracking or usage boosts.

        // Aliases.
        //
        // Two flavours:
        //   * Plain (no `{query}` in value): fuzzy-matched against the
        //     alias key like everything else.
        //   * Parameterized (value contains `{query}`): triggers in command
        //     mode — the user types "<key> <rest>" and `<rest>` is
        //     substituted into the value. When a parameterized alias is
        //     hit we skip the rest of the scored pool so a YouTube search
        //     ("y cat videos") doesn't surface unrelated app matches for
        //     "cat" or "videos". Web fallback still appears at the bottom.
        var parameterizedAliasMatched = false
        if let aliases = config?.aliases {
            let ql = q.lowercased()

            // First, look for a "<key> <rest>" parameterized hit. This wins
            // over plain alias matches because the user's intent is explicit.
            if let firstSpace = q.firstIndex(of: " ") {
                let key = String(q[..<firstSpace]).lowercased()
                let rest = String(q[q.index(after: firstSpace)...]).trimmingCharacters(in: .whitespaces)
                if let value = aliases[key], value.contains("{query}"), !rest.isEmpty,
                   BrowserURL.parse(value.replacingOccurrences(of: "{query}", with: "x")) != nil {
                    let displayName = config?.aliasNames[key] ?? key
                    let result = makeParameterizedAliasResult(displayName: displayName, value: value, query: rest)
                    pinnedTop.append(result)
                    parameterizedAliasMatched = true
                }
            }

            if !parameterizedAliasMatched {
                for (key, value) in aliases {
                    // Skip parameterized aliases when the user hasn't typed
                    // a query yet — showing them with no value is noise.
                    guard !value.contains("{query}"), ConfigManager.isAllowedAliasValue(value) else { continue }

                    let match = fuzzyMatch(query: ql, target: key)
                    guard match.matched else { continue }

                    var icon: NSImage? = NSImage(systemSymbolName: "link", accessibilityDescription: "Alias")
                    let action: ResultAction
                    let subtitle: String

                    if BrowserURL.parse(value) != nil {
                        action = .url(value)
                        subtitle = value
                    } else {
                        action = .openApp(value)
                        subtitle = value
                    }

                    let displayName = config?.aliasNames[key] ?? key
                    let result = SearchResult(title: displayName, subtitle: subtitle, icon: icon, action: action)
                    scored.append((result, Double(match.score)))
                }
            }
        }

        // Skip the rest of the scored pool if a parameterized alias is
        // active — the user's intent is explicit, no need to suggest
        // unrelated apps that happen to fuzzy-match the alias arguments.
        if parameterizedAliasMatched {
            var results = pinnedTop
            // Still emit the web fallback so the user can escape to a
            // generic search if they typed the wrong alias key.
            results.append(makeWebFallback(query: q))
            return results
        }

        // "Change Theme" entry — fuzzy on a fixed label.
        let themeMatch = fuzzyMatch(query: q, target: "Change Theme")
        if themeMatch.matched {
            let icon = NSImage(systemSymbolName: "paintpalette", accessibilityDescription: "Theme")
            let result = SearchResult(
                title: "Change Theme",
                subtitle: "Browse and apply built-in themes",
                icon: icon,
                action: .enterThemePicker
            )
            scored.append((result, Double(themeMatch.score)))
        }

        // System Settings panes.
        for item in prefPanes.search(query: q) {
            let icon = NSImage(systemSymbolName: item.pane.iconName, accessibilityDescription: item.pane.name)
            let result = SearchResult(
                title: item.pane.name,
                subtitle: "System Settings",
                icon: icon,
                action: .settings(item.pane.url)
            )
            scored.append((result, Double(item.score)))
        }

        // Apps, ranked only by the current query and candidate name.
        let excluded = Set(config?.search.excludedApps.map { $0.lowercased() } ?? [])
        let showPath = config?.search.showPath ?? true
        for entry in appIndex.allEntries {
            if excluded.contains(entry.nameLower) { continue }
            let match = fuzzyMatch(query: q, target: entry.name)
            guard match.matched else { continue }
            let result = SearchResult(
                title: entry.name,
                subtitle: showPath ? entry.path : "",
                icon: entry.icon,
                action: .openApp(entry.path)
            )
            scored.append((result, Double(match.score)))
        }

        scored.sort {
            if $0.score != $1.score { return $0.score > $1.score }
            return $0.result.title.localizedCaseInsensitiveCompare($1.result.title) == .orderedAscending
        }

        var results = pinnedTop
        results += scored.prefix(25).map { $0.result }

        // ----- Pinned bottom: web search fallback -----------------------

        results.append(makeWebFallback(query: q))

        return results
    }

    /// Only validated HTTP(S) templates can reach this helper.
    private func makeParameterizedAliasResult(displayName: String, value: String, query: String) -> SearchResult {
        let url = value.replacingOccurrences(of: "{query}", with: BrowserURL.encodeQuery(query))
        return SearchResult(title: "\(displayName) → \(query)", subtitle: url,
            icon: NSImage(systemSymbolName: "link", accessibilityDescription: "Alias"), action: .url(url))
    }

    /// Builds the trailing web-search fallback result. Honors the user's
    /// configured engine, which may be a built-in name (google/ddg/bing)
    /// or a full URL template containing `{query}`.
    private func makeWebFallback(query: String) -> SearchResult {
        let encoded = BrowserURL.encodeQuery(query)
        let engine = config?.search.webSearch ?? "google"
        let (engineName, webURL) = searchEngineURL(engine: engine, query: encoded)
        let webIcon = NSImage(systemSymbolName: "magnifyingglass.circle", accessibilityDescription: "Web search")
        return SearchResult(
            title: "Search \(engineName) for \"\(query)\"",
            subtitle: "Open in default browser",
            icon: webIcon,
            action: .url(webURL)
        )
    }

    /// Executes a result action without recording query or usage data.
    func launch(result: SearchResult) {
        switch result.action {
        case .openApp(let path):
            apps.launch(path: path, open: { url in
                NSWorkspace.shared.open(url)
            })
        case .url(let urlString):
            if let url = BrowserURL.parse(urlString) { NSWorkspace.shared.open(url) }
        case .settings(let value):
            if prefPanes.panes.contains(where: { $0.url == value }), let url = URL(string: value) {
                NSWorkspace.shared.open(url)
            }
        case .copy(let text):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        case .enterThemePicker, .applyTheme:
            // Handled by LauncherPanelController, not here
            break
        }
    }

    func themeResults(filter: String) -> [SearchResult] {
        guard let config else { return [] }
        let icon = NSImage(systemSymbolName: "paintpalette", accessibilityDescription: "Theme")
        let q = filter.trimmingCharacters(in: .whitespaces)
        return config.allThemes.keys.sorted().compactMap { name in
            guard q.isEmpty || fuzzyMatch(query: q, target: name).matched else { return nil }
            let title = name.split(separator: "-").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
            let group = config.userThemes[name] == nil ? "Built-in" : "Custom"
            return SearchResult(title: title, subtitle: group + (config.theme.name == name ? " — current" : ""),
                icon: icon, action: .applyTheme(name))
        }
    }

    /// Theme confirmation writes only the existing config file.
    func applyTheme(name: String) {
        config?.selectTheme(name)
    }

    /// Resolves the configured `engine` string into a (display name, URL)
    /// pair. Accepts either a built-in name (google / duckduckgo / bing)
    /// or a full URL template containing `{query}` — `query` is already
    /// URL-encoded by the caller.
    private func searchEngineURL(engine: String, query: String) -> (name: String, url: String) {
        if engine.contains("{query}"), BrowserURL.parse(engine.replacingOccurrences(of: "{query}", with: "x")) != nil {
            let url = engine.replacingOccurrences(of: "{query}", with: query)
            // Pretty-print the host so the result line reads "Search
            // youtube.com for ..." instead of repeating the full URL.
            let name = URL(string: url)?.host?.replacingOccurrences(of: "www.", with: "") ?? "Web"
            return (name, url)
        }
        switch engine.lowercased() {
        case "duckduckgo", "ddg":
            return ("DuckDuckGo", "https://duckduckgo.com/?q=\(query)")
        case "bing":
            return ("Bing", "https://www.bing.com/search?q=\(query)")
        default:
            return ("Google", "https://www.google.com/search?q=\(query)")
        }
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
