// Local TOML-subset config and themes. No preferences or legacy data access.
import Foundation

final class ConfigManager {
    struct Theme {
        var name: String?
        var background = "#1e1e2e"
        var foreground = "#cdd6f4"
        var accent = "#cba6f7"
        var selection: String?
        var subtitle: String?
        var border: String?
        var placeholderColor: String?
        var borderRadius: Float = 12
        var font = "SF Pro"
        var fontSize = 14
        var fontWeight = "medium"
        var blurMaterial = "hudWindow"
    }
    struct Layout {
        var width = 780
        var maxResults = 8
        var placeholder = "Search apps, calculate, convert..."
        var mode = "list"
    }
    struct Keybindings {
        var open = "Cmd+Space"
        var close = "Escape"
    }
    struct Search {
        var webSearch = "google"
        var showPath = true
        var excludedApps: [String] = []
    }

    var theme = Theme()
    var layout = Layout()
    var keybindings = Keybindings()
    var search = Search()
    var aliases: [String: String] = [:]
    var aliasNames: [String: String] = [:]
    var userThemes: [String: ThemePreset] = [:]
    var allThemes: [String: ThemePreset] { builtinThemes.merging(userThemes) { _, user in user } }
    var onChange: (() -> Void)?
    let configURL: URL
    var userThemesDir: URL { configURL.deletingLastPathComponent().appendingPathComponent("themes") }
    private let apps: AllowedApps
    private var monitors: [DispatchSourceFileSystemObject] = []
    private var pendingReload: DispatchWorkItem?
    private var watching = false

    // Fixed default sizing; no configurable scale or persisted geometry.
    func s(_ base: CGFloat) -> CGFloat { base }

    init(configURL: URL? = nil, watchForChanges: Bool = true, apps: AllowedApps = AllowedApps()) {
        self.configURL = configURL ?? ProcessInfo.processInfo.environment["WALTER_CONFIG"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/walter/config.toml")
        self.apps = apps
        ensureConfigExists()
        ensureUserThemesDirExists()
        load()
        if watchForChanges { startWatching() }
    }

    deinit { stopWatching() }

    func reload() {
        theme = Theme(); layout = Layout(); keybindings = Keybindings(); search = Search()
        aliases = [:]; aliasNames = [:]; userThemes = [:]
        load()
        onChange?()
    }

    // Pure preliminary guard. App existence and resolved boundaries are checked
    // during config loading and again at activation, not on each keystroke.
    static func isAllowedAliasValue(_ value: String, appRoot: String = "/Applications") -> Bool {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("!") else { return false }
        if value.contains("{query}") {
            return BrowserURL.parse(value.replacingOccurrences(of: "{query}", with: "x")) != nil
        }
        return BrowserURL.parse(value) != nil ||
            (value.hasPrefix(appRoot + "/") && value.lowercased().hasSuffix(".app") && !value.contains("/../"))
    }

    private func storeAlias(_ key: String, _ value: String) {
        let browser = BrowserURL.parse(value.replacingOccurrences(of: "{query}", with: "x")) != nil
        if !value.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("!"), browser {
            aliases[key.lowercased()] = value
        } else if !value.contains("{query}"), let url = apps.validatedURL(for: value) {
            aliases[key.lowercased()] = url.path
        } else {
            aliases.removeValue(forKey: key.lowercased())
        }
    }

    private func ensureConfigExists() {
        guard !FileManager.default.fileExists(atPath: configURL.path) else { return }
        try? FileManager.default.createDirectory(at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Self.defaultConfig.write(to: configURL, atomically: true, encoding: .utf8)
    }

    static let defaultConfig = """
    # Walter — local configuration. Changes apply live on save.
    # Unknown/removed keys are ignored. No history, caches, or preferences.
    [theme]
    # name = "catppuccin-mocha"
    background = "#1e1e2e"
    foreground = "#cdd6f4"
    accent = "#cba6f7"
    # selection = "#45475a"
    # subtitle = "#6c7086"
    # border = "#313244"
    # placeholder_color = "#6c7086"
    border_radius = 12
    font = "SF Pro"
    font_size = 14
    font_weight = "medium"
    blur_material = "hudWindow"

    [layout]
    width = 780
    max_results = 8
    placeholder = "Search apps, calculate, convert..."
    mode = "list" # list | grid

    [keybindings]
    open = "Cmd+Space"
    close = "Escape"

    [search]
    web_search = "google" # google | duckduckgo | bing | https://...{query}...
    show_path = true
    # excluded_apps = Example, Another App

    # Only HTTP(S) URLs or real apps resolved inside /Applications.
    # Commands (!), arbitrary paths, and parameterized app paths are rejected.
    [aliases]
    # gh = "https://github.com"
    # example = "/Applications/Example.app"

    # Optional display name and URL template. Arguments are URL-encoded.
    # [aliases.y]
    # name = "YouTube"
    # url = "https://www.youtube.com/results?search_query={query}"
    """

    private func ensureUserThemesDirExists() {
        try? FileManager.default.createDirectory(at: userThemesDir, withIntermediateDirectories: true)
        let example = userThemesDir.appendingPathComponent("example.theme")
        guard !FileManager.default.fileExists(atPath: example.path) else { return }
        try? """
        # Custom theme. Filename is its theme name; lines beginning # are comments.
        background #1a1a2e
        foreground #eaeaea
        accent #ff6b6b
        """.write(to: example, atomically: true, encoding: .utf8)
    }

    private func load() {
        userThemes = loadUserThemes(from: userThemesDir)
        guard let content = try? String(contentsOf: configURL, encoding: .utf8) else { return }
        var section = ""
        var aliasKey: String?
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            if trimmed.hasPrefix("["), trimmed.hasSuffix("]") {
                section = String(trimmed.dropFirst().dropLast())
                aliasKey = section.hasPrefix("aliases.") ? String(section.dropFirst(8)).lowercased() : nil
                continue
            }
            let parts = trimmed.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespaces)
            var raw = parts[1].trimmingCharacters(in: .whitespaces)
            let quotes: Set<Character> = ["\"", "\u{201C}", "\u{201D}"]
            if let first = raw.first, quotes.contains(first) {
                if let close = raw.dropFirst().firstIndex(where: { quotes.contains($0) }) { raw = String(raw[...close]) }
            } else if let comment = raw.firstIndex(of: "#") {
                raw = String(raw[..<comment]).trimmingCharacters(in: .whitespaces)
            }
            let value = raw.trimmingCharacters(in: CharacterSet(charactersIn: "\"\u{201C}\u{201D}"))
            if let aliasKey {
                if key == "name" { aliasNames[aliasKey] = value }
                else if ["url", "value", "path"].contains(key) { storeAlias(aliasKey, value) }
                continue
            }
            if section == "aliases" { storeAlias(key, value); continue }
            switch (section, key) {
            case ("theme", "name"): theme.name = value
            case ("theme", "background"): theme.background = value
            case ("theme", "foreground"): theme.foreground = value
            case ("theme", "accent"): theme.accent = value
            case ("theme", "selection"): theme.selection = value
            case ("theme", "subtitle"): theme.subtitle = value
            case ("theme", "border"): theme.border = value
            case ("theme", "placeholder_color"): theme.placeholderColor = value
            case ("theme", "border_radius"): if let n = Float(value), n.isFinite { theme.borderRadius = min(100, max(0, n)) }
            case ("theme", "font"): theme.font = value
            case ("theme", "font_size"): theme.fontSize = min(72, max(8, Int(value) ?? 14))
            case ("theme", "font_weight"): theme.fontWeight = value
            case ("theme", "blur_material"): theme.blurMaterial = value
            case ("layout", "width"): layout.width = min(2400, max(320, Int(value) ?? 780))
            case ("layout", "max_results"): layout.maxResults = min(25, max(1, Int(value) ?? 8))
            case ("layout", "placeholder"): layout.placeholder = value
            case ("layout", "mode"): layout.mode = value.lowercased() == "grid" ? "grid" : "list"
            case ("keybindings", "open"): keybindings.open = value
            case ("keybindings", "close"): keybindings.close = value
            case ("search", "web_search"): search.webSearch = value
            case ("search", "show_path"): search.showPath = value == "true"
            case ("search", "excluded_apps"): search.excludedApps = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            default: break
            }
        }
        if let name = theme.name?.lowercased(), let preset = allThemes[name] {
            theme.background = preset.background; theme.foreground = preset.foreground; theme.accent = preset.accent
            if let s = preset.selection { theme.selection = s }
            if let s = preset.subtitle { theme.subtitle = s }
            if let b = preset.border { theme.border = b }
        }
    }

    /// Only known local theme names can be written; preserve unrelated config.
    func selectTheme(_ name: String) {
        guard allThemes[name] != nil,
              name.rangeOfCharacter(from: CharacterSet(charactersIn: "\"\r\n\u{201C}\u{201D}")) == nil,
              let content = try? String(contentsOf: configURL, encoding: .utf8) else { return }
        var lines: [String] = []
        var inTheme = false
        var written = false
        var foundSection = false
        for line in content.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("["), trimmed.hasSuffix("]") {
                if inTheme && !written { lines.append("name = \"\(name)\""); written = true }
                inTheme = trimmed == "[theme]"
                foundSection = foundSection || inTheme
            }
            let key = trimmed.split(separator: "=", maxSplits: 1).first?.trimmingCharacters(in: .whitespaces)
            if inTheme && (key == "name" || key == "# name") {
                if !written { lines.append("name = \"\(name)\""); written = true }
            } else { lines.append(line) }
        }
        if !written {
            if !foundSection { lines.append("[theme]") }
            lines.append("name = \"\(name)\"")
        }
        try? lines.joined(separator: "\n").write(to: configURL, atomically: true, encoding: .utf8)
    }

    private func startWatching() {
        watching = true
        // Watch the parent directory so atomic config replacement stays covered.
        for url in [configURL.deletingLastPathComponent(), userThemesDir] {
            let fd = open(url.path, O_EVTONLY)
            guard fd >= 0 else { continue }
            let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
            source.setCancelHandler { close(fd) }
            source.setEventHandler { [weak self] in
                guard let self, self.watching else { return }
                self.pendingReload?.cancel()
                let work = DispatchWorkItem { [weak self] in
                    guard let self, self.watching else { return }
                    // Reattach if the theme directory itself was replaced.
                    self.stopWatching()
                    self.startWatching()
                    self.reload()
                }
                self.pendingReload = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
            }
            source.resume()
            monitors.append(source)
        }
    }

    /// Explicit shutdown also prevents delayed callbacks from reviving watchers.
    func stopWatching() {
        watching = false
        pendingReload?.cancel(); pendingReload = nil
        for source in monitors { source.cancel() }
        monitors.removeAll()
    }
}
