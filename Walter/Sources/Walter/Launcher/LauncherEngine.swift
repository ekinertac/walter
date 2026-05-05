// LauncherEngine.swift — Core search and launch logic
//
// Result sources (in display order):
//   1. Calculator (if query looks like math)
//   2. Currency / unit conversion (if query matches pattern)
//   3. Aliases (exact prefix match from [aliases] config)
//   4. System commands (lock, sleep, restart, etc.)
//   5. System Settings panes (Bluetooth, Display, ...)
//   6. Apps (fuzzy matched, frecency-boosted)
//   7. Web search fallback (always last)
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

        var results: [SearchResult] = []

        // 1. Currency / unit conversion (checked first — "100 km in miles"
        //    should not trigger the calculator)
        let conversions = converter.convert(query: q)
        if !conversions.isEmpty {
            let icon = NSImage(systemSymbolName: "arrow.left.arrow.right", accessibilityDescription: "Convert")
            results += conversions.map { conv in
                SearchResult(
                    title: conv.title,
                    subtitle: "\(conv.subtitle) — Enter to copy",
                    icon: icon,
                    action: .copy(conv.copyValue)
                )
            }
        }

        // 2. Calculator (skip if converter already matched — avoids
        //    "1920x1080" showing both a conversion and a multiplication)
        if conversions.isEmpty, let calc = calculator.evaluate(query: q) {
            let icon = NSImage(systemSymbolName: "equal.circle", accessibilityDescription: "Calculator")
            results.append(SearchResult(
                title: calc.answer,
                subtitle: "\(calc.expression) — Enter to copy",
                icon: icon,
                action: .copy(calc.answer)
            ))
        }

        // 3. Aliases from config
        if let aliases = config?.aliases {
            let ql = q.lowercased()
            for (key, value) in aliases {
                guard fuzzyMatch(query: ql, target: key).matched else { continue }
                let icon = NSImage(systemSymbolName: "link", accessibilityDescription: "Alias")
                let action: ResultAction
                let subtitle: String

                if value.hasPrefix("!") {
                    // Shell command alias: !curl -s ifconfig.me
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

                results.append(SearchResult(title: key, subtitle: subtitle, icon: icon, action: action))
            }
        }

        // 4. "Change Theme" action — fuzzy matched like any other result
        let themeMatch = fuzzyMatch(query: q, target: "Change Theme")
        if themeMatch.matched {
            let icon = NSImage(systemSymbolName: "paintpalette", accessibilityDescription: "Theme")
            results.append(SearchResult(
                title: "Change Theme",
                subtitle: "Browse and apply built-in themes",
                icon: icon,
                action: .enterThemePicker
            ))
        }

        // 5. System commands
        if config?.search.showSystemCommands != false {
            let sysResults = systemCommands.search(query: q)
            for item in sysResults.prefix(4) {
                let icon = NSImage(systemSymbolName: item.command.iconName, accessibilityDescription: item.command.name)
                results.append(SearchResult(
                    title: item.command.name,
                    subtitle: item.command.subtitle,
                    icon: icon,
                    action: .systemCommand(item.command)
                ))
            }
        }

        // 5b. System Settings panes (Bluetooth, Display, Network, ...).
        //     Surfaced before apps so "Bluetooth" matches the pane, not a
        //     random app. Capped at top 4 to avoid drowning out apps.
        let paneResults = prefPanes.search(query: q)
        for item in paneResults.prefix(4) {
            let icon = NSImage(systemSymbolName: item.pane.iconName, accessibilityDescription: item.pane.name)
            results.append(SearchResult(
                title: item.pane.name,
                subtitle: "System Settings",
                icon: icon,
                action: .url(item.pane.url)
            ))
        }

        // 6. Apps (fuzzy + frecency)
        let excluded = Set(config?.search.excludedApps.map { $0.lowercased() } ?? [])
        var scored: [(entry: AppEntry, score: Double)] = []

        for entry in appIndex.allEntries {
            if excluded.contains(entry.nameLower) { continue }
            let result = fuzzyMatch(query: q, target: entry.name)
            guard result.matched else { continue }
            let frecencyBoost = frecency.score(for: entry.path) * 10
            scored.append((entry, Double(result.score) + frecencyBoost))
        }

        scored.sort { $0.score > $1.score }

        let showPath = config?.search.showPath ?? true
        results += scored.prefix(20).map { item in
            SearchResult(
                title: item.entry.name,
                subtitle: showPath ? item.entry.path : "",
                icon: item.entry.icon,
                action: .open(item.entry.path)
            )
        }

        // 7. Web search fallback
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

    /// Returns all built-in themes as results, filtered by query.
    /// Used when the UI is in theme-picker mode.
    func themeResults(filter: String) -> [SearchResult] {
        let currentTheme = config?.theme.name?.lowercased()
        let icon = NSImage(systemSymbolName: "paintpalette", accessibilityDescription: "Theme")

        let allThemes: [(name: String, group: String)] =
            [("spotlight", "System"),
             ("catppuccin-mocha", "Dark"), ("catppuccin-macchiato", "Dark"),
             ("catppuccin-frappe", "Dark"), ("catppuccin-latte", "Light"),
             ("nord", "Dark"), ("dracula", "Dark"), ("gruvbox", "Dark"),
             ("solarized-dark", "Dark"), ("solarized-light", "Light"),
             ("rose-pine", "Dark"), ("rose-pine-moon", "Dark"), ("rose-pine-dawn", "Light"),
             ("tokyo-night", "Dark"), ("one-dark", "Dark"), ("kanagawa", "Dark"),
             ("everforest", "Dark"), ("everforest-light", "Light"),
             ("ayu-dark", "Dark"), ("ayu-light", "Light"), ("github-light", "Light")]

        let q = filter.trimmingCharacters(in: .whitespaces)

        return allThemes.compactMap { theme in
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
