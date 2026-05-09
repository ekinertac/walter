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

        // Aliases — fuzzy on the alias key.
        if let aliases = config?.aliases {
            let ql = q.lowercased()
            for (key, value) in aliases {
                let match = fuzzyMatch(query: ql, target: key)
                guard match.matched else { continue }

                let icon = NSImage(systemSymbolName: "link", accessibilityDescription: "Alias")
                let action: ResultAction
                let subtitle: String

                if value.hasPrefix("!") {
                    let cmd = String(value.dropFirst())
                    action = .shell(cmd)
                    subtitle = "Run: \(cmd)"
                } else if value.hasPrefix("http://") || value.hasPrefix("https://") {
                    action = .url(value)
                    subtitle = value
                } else {
                    action = .open(value)
                    subtitle = value
                }

                let result = SearchResult(title: key, subtitle: subtitle, icon: icon, action: action)
                scored.append((result, Double(match.score)))
            }
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
        let excluded = Set(config?.search.excludedApps.map { $0.lowercased() } ?? [])
        let showPath = config?.search.showPath ?? true
        for entry in appIndex.allEntries {
            if excluded.contains(entry.nameLower) { continue }
            let match = fuzzyMatch(query: q, target: entry.name)
            guard match.matched else { continue }
            let frecencyBoost = frecency.score(for: entry.path) * 10
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

        let encoded = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? q
        let engine = config?.search.engine ?? "google"
        let (engineName, webURL) = searchEngineURL(engine: engine, query: encoded)
        let webIcon = NSImage(systemSymbolName: "magnifyingglass.circle", accessibilityDescription: "Web search")
        results.append(SearchResult(
            title: "Search \(engineName) for \"\(q)\"",
            subtitle: "Open in default browser",
            icon: webIcon,
            action: .url(webURL)
        ))

        return results
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

    private func searchEngineURL(engine: String, query: String) -> (name: String, url: String) {
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
