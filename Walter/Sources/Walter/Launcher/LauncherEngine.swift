// LauncherEngine.swift — Core search and launch logic
//
// Result layout:
//   1. Calculator / converter answers — pinned to the top because they
//      are computed answers, not search results, and there is nothing
//      meaningful to score them against.
//   2. A unified pool of fuzzy-scored results — apps, system commands,
//      System Settings panes, aliases, and the "Change Theme" action all
//      compete in one ranked list. Apps additionally receive a frecency
//      boost so frequently-launched apps win against equally-named items
//      from other categories.
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
    case open(String)
    case shell(String)
    case copy(String)
    case url(String)
    case systemCommand(SystemCommand)
    case enterThemePicker          // switches UI to theme browsing mode
    case applyTheme(String)        // applies a theme by name and writes to config
}

class LauncherEngine {

    private let appIndex: AppIndex
    private let frecency = FrecencyTracker()
    private let calculator = Calculator()
    private let converter = Converter()
    private let prefPanes = PrefPaneIndex()
    private var systemCommands: SystemCommands!
    private weak var config: ConfigManager?

    init(config: ConfigManager, extraAppDirs: [String] = [], onIndexChanged: @escaping () -> Void = {}) {
        self.config = config
        systemCommands = SystemCommands(config: config)
        appIndex = AppIndex(extraDirs: extraAppDirs, onChange: onIndexChanged)
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

        // ----- Scored pool: apps, sys cmds, panes, aliases, theme entry --
        // All searchable items live in a single ranked list keyed by the
        // fuzzy score against the query. Apps additionally receive a
        // frecency boost so a heavily-used app outranks an unrelated
        // pane / alias / system command with the same prefix.

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
                if let value = aliases[key], value.contains("{query}"), !rest.isEmpty {
                    let displayName = config?.aliasNames[key] ?? key
                    let result = makeParameterizedAliasResult(displayName: displayName, value: value, query: rest)
                    pinnedTop.append(result)
                    parameterizedAliasMatched = true
                    // Trigger fetch for newly-encountered aliases so the
                    // next render picks up the favicon even if config
                    // wasn't reloaded since the alias was added.
                    if let host = FaviconCache.hostname(for: value) {
                        FaviconCache.shared.prefetch(hostnames: [host])
                    }
                }
            }

            if !parameterizedAliasMatched {
                for (key, value) in aliases {
                    // Skip parameterized aliases when the user hasn't typed
                    // a query yet — showing them with no value is noise.
                    if value.contains("{query}") { continue }

                    let match = fuzzyMatch(query: ql, target: key)
                    guard match.matched else { continue }

                    var icon: NSImage? = NSImage(systemSymbolName: "link", accessibilityDescription: "Alias")
                    let action: ResultAction
                    let subtitle: String

                    if value.hasPrefix("!") {
                        let cmd = String(value.dropFirst())
                        action = .shell(cmd)
                        subtitle = "Run: \(cmd)"
                    } else if value.hasPrefix("http://") || value.hasPrefix("https://") {
                        action = .url(value)
                        subtitle = value
                        if let host = FaviconCache.hostname(for: value),
                           let favicon = FaviconCache.shared.image(for: host) {
                            icon = favicon
                        }
                    } else {
                        action = .open(value)
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

        // System commands.
        if config?.search.showSystemCommands != false {
            for item in systemCommands.search(query: q) {
                let icon = NSImage(systemSymbolName: item.command.iconName, accessibilityDescription: item.command.name)
                let result = SearchResult(
                    title: item.command.name,
                    subtitle: item.command.subtitle,
                    icon: icon,
                    action: .systemCommand(item.command)
                )
                scored.append((result, Double(item.score)))
            }
        }

        // System Settings panes.
        for item in prefPanes.search(query: q) {
            let icon = NSImage(systemSymbolName: item.pane.iconName, accessibilityDescription: item.pane.name)
            let result = SearchResult(
                title: item.pane.name,
                subtitle: "System Settings",
                icon: icon,
                action: .url(item.pane.url)
            )
            scored.append((result, Double(item.score)))
        }

        // Apps with frecency boost.
        // The boost is capped so heavy use of one app cannot drown out a
        // better-matching different app. Without the cap, opening the
        // launcher and typing "to" while Stremio has been launched
        // dozens of times would always surface Stremio above Tolaria,
        // even though "to" is a clean prefix of Tolaria and a poor
        // scattered match in Stremio. The cap is comparable to the
        // prefix-match bonus, so frecency tunes ranking among similar
        // matches but cannot overwhelm a clearly stronger candidate.
        let excluded = Set(config?.search.excludedApps.map { $0.lowercased() } ?? [])
        let showPath = config?.search.showPath ?? true
        let maxFrecencyBoost: Double = 40
        for entry in appIndex.allEntries {
            if excluded.contains(entry.nameLower) { continue }
            let match = fuzzyMatch(query: q, target: entry.name)
            guard match.matched else { continue }
            let rawBoost = frecency.score(for: entry.path) * 10
            let frecencyBoost = min(rawBoost, maxFrecencyBoost)
            let result = SearchResult(
                title: entry.name,
                subtitle: showPath ? entry.path : "",
                icon: entry.icon,
                action: .open(entry.path)
            )
            scored.append((result, Double(match.score) + frecencyBoost))
        }

        scored.sort { $0.score > $1.score }

        var results = pinnedTop
        results += scored.prefix(25).map { $0.result }

        // ----- Pinned bottom: web search fallback -----------------------

        results.append(makeWebFallback(query: q))

        return results
    }

    /// Builds a search result for the parameterized alias that just matched.
    /// `value` is the raw alias value (URL, !shell, or path) with `{query}`
    /// placeholders; `query` is the text the user typed after the alias key.
    private func makeParameterizedAliasResult(displayName: String, value: String, query: String) -> SearchResult {
        let action: ResultAction
        let subtitle: String
        var icon: NSImage? = NSImage(systemSymbolName: "link", accessibilityDescription: "Alias")

        if value.hasPrefix("!") {
            let cmd = String(value.dropFirst()).replacingOccurrences(of: "{query}", with: query)
            action = .shell(cmd)
            subtitle = "Run: \(cmd)"
        } else if value.hasPrefix("http://") || value.hasPrefix("https://") {
            let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
            let url = value.replacingOccurrences(of: "{query}", with: encoded)
            action = .url(url)
            subtitle = url
            // Site favicon if we have one cached; otherwise the link symbol.
            if let host = FaviconCache.hostname(for: value),
               let favicon = FaviconCache.shared.image(for: host) {
                icon = favicon
            }
        } else {
            let path = value.replacingOccurrences(of: "{query}", with: query)
            action = .open(path)
            subtitle = path
        }

        return SearchResult(
            title: "\(displayName) → \(query)",
            subtitle: subtitle,
            icon: icon,
            action: action
        )
    }

    /// Builds the trailing web-search fallback result. Honors the user's
    /// configured engine, which may be a built-in name (google/ddg/bing)
    /// or a full URL template containing `{query}`.
    private func makeWebFallback(query: String) -> SearchResult {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let engine = config?.search.engine ?? "google"
        let (engineName, webURL) = searchEngineURL(engine: engine, query: encoded)
        let webIcon = NSImage(systemSymbolName: "magnifyingglass.circle", accessibilityDescription: "Web search")
        return SearchResult(
            title: "Search \(engineName) for \"\(query)\"",
            subtitle: "Open in default browser",
            icon: webIcon,
            action: .url(webURL)
        )
    }

    /// Executes a result action and records frecency for app launches.
    func launch(result: SearchResult) {
        switch result.action {
        case .open(let path):
            frecency.recordLaunch(path: path)
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
        case .url(let urlString):
            if let url = URL(string: urlString) {
                NSWorkspace.shared.open(url)
            }
        case .shell(let command):
            let task = Process()
            task.launchPath = "/bin/sh"
            task.arguments = ["-c", command]
            try? task.run()
        case .copy(let text):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        case .systemCommand(let cmd):
            if cmd.needsConfirmation {
                guard SystemCommands.confirm(action: cmd.name) else { return }
            }
            cmd.action()
        case .enterThemePicker, .applyTheme:
            // Handled by LauncherPanelController, not here
            break
        }
    }

    /// Returns themes (built-in + user-defined) as picker results,
    /// filtered by query. Used when the UI is in theme-picker mode.
    /// Built-ins keep their curated order; user themes follow alphabetically
    /// under a "Custom" group label.
    func themeResults(filter: String) -> [SearchResult] {
        let currentTheme = config?.theme.name?.lowercased()
        let icon = NSImage(systemSymbolName: "paintpalette", accessibilityDescription: "Theme")

        let builtins: [(name: String, group: String)] =
            [("spotlight", "System"),
             ("catppuccin-mocha", "Dark"), ("catppuccin-macchiato", "Dark"),
             ("catppuccin-frappe", "Dark"), ("catppuccin-latte", "Light"),
             ("nord", "Dark"), ("dracula", "Dark"), ("gruvbox", "Dark"),
             ("solarized-dark", "Dark"), ("solarized-light", "Light"),
             ("rose-pine", "Dark"), ("rose-pine-moon", "Dark"), ("rose-pine-dawn", "Light"),
             ("tokyo-night", "Dark"), ("one-dark", "Dark"), ("kanagawa", "Dark"),
             ("everforest", "Dark"), ("everforest-light", "Light"),
             ("ayu-dark", "Dark"), ("ayu-light", "Light"), ("github-light", "Light")]

        let userNames = (config?.userThemes.keys ?? Dictionary<String, ThemePreset>().keys)
            .sorted()

        // Built-ins first, then user themes (excluding any name collisions
        // that would already be displayed under a built-in slot).
        let builtinNames = Set(builtins.map { $0.name })
        let combined: [(name: String, group: String)] =
            builtins + userNames
                .filter { !builtinNames.contains($0) }
                .map { ($0, "Custom") }

        let q = filter.trimmingCharacters(in: .whitespaces)

        return combined.compactMap { theme in
            if !q.isEmpty {
                let match = fuzzyMatch(query: q, target: theme.name)
                guard match.matched else { return nil }
            }
            let displayName = theme.name.split(separator: "-")
                .map { $0.prefix(1).uppercased() + $0.dropFirst() }
                .joined(separator: " ")
            let isCurrent = theme.name == currentTheme
            let subtitle = "\(theme.group)\(isCurrent ? " — current" : "")"
            return SearchResult(
                title: displayName,
                subtitle: subtitle,
                icon: icon,
                action: .applyTheme(theme.name)
            )
        }
    }

    /// Writes the theme name into config.toml. Hot-reload picks it up.
    func applyTheme(name: String) {
        guard let config = config else { return }
        let url = config.configURL
        guard var content = try? String(contentsOf: url, encoding: .utf8) else { return }

        let lines = content.components(separatedBy: "\n")
        var result: [String] = []
        var inTheme = false
        var nameWritten = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                if inTheme && !nameWritten {
                    result.append("name = \"\(name)\"")
                    nameWritten = true
                }
                let section = String(trimmed.dropFirst().dropLast())
                inTheme = (section == "theme")
            }

            if inTheme {
                let key = trimmed.split(separator: "=", maxSplits: 1).first?
                    .trimmingCharacters(in: .whitespaces) ?? ""
                if key == "name" || key == "# name" {
                    result.append("name = \"\(name)\"")
                    nameWritten = true
                    continue
                }
            }

            result.append(line)
        }

        if !nameWritten {
            // Shouldn't happen, but just in case
            result.insert("name = \"\(name)\"", at: result.firstIndex(of: "[theme]")?.advanced(by: 1) ?? result.endIndex)
        }

        content = result.joined(separator: "\n")
        try? content.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Resolves the configured `engine` string into a (display name, URL)
    /// pair. Accepts either a built-in name (google / duckduckgo / bing)
    /// or a full URL template containing `{query}` — `query` is already
    /// URL-encoded by the caller.
    private func searchEngineURL(engine: String, query: String) -> (name: String, url: String) {
        if engine.contains("{query}") {
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
