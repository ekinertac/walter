// ConfigManager.swift — Loads config.toml into typed structs
//
// Reads from ~/.config/walter/config.toml. Falls back to sensible defaults
// if the file is missing or any field is absent. Uses a minimal hand-rolled
// TOML parser (good enough for flat key=value sections) to avoid pulling in
// a full TOML library dependency.
//
// The Lua theme layer (theme.lua) will be added in a later iteration.
//
// Related: config-example/config.toml for the documented format.

import Foundation

class ConfigManager {

    struct Theme {
        var background: String = "#1e1e2e"
        var foreground: String = "#cdd6f4"
        var accent: String = "#cba6f7"
        var borderRadius: Float = 12.0
        var font: String = "SF Pro"
        var fontSize: Int = 14
    }

    struct Layout {
        var width: Int = 780
        var maxResults: Int = 8
        var position: String = "center"
        /// Multiplier for all UI dimensions. 1.0 = default, 1.5 = 50% bigger, etc.
        var scale: Float = 1.0
    }

    struct Keybindings {
        var open: String = "Alt+Space"
        var close: String = "Escape"
    }

    var theme = Theme()
    var layout = Layout()
    var keybindings = Keybindings()

    /// Scale a base dimension by the layout.scale factor.
    /// Usage: `config.s(28)` → 28 at scale 1.0, 42 at scale 1.5
    func s(_ base: CGFloat) -> CGFloat {
        base * CGFloat(layout.scale)
    }

    init() {
        ensureConfigExists()
        load()
    }

    private var configURL: URL {
        if let env = ProcessInfo.processInfo.environment["WALTER_CONFIG"] {
            return URL(fileURLWithPath: env)
        }
        let configDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/walter")
        return configDir.appendingPathComponent("config.toml")
    }

    /// Creates ~/.config/walter/config.toml with documented defaults on first run.
    private func ensureConfigExists() {
        let url = configURL
        guard !FileManager.default.fileExists(atPath: url.path) else { return }

        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let defaults = """
        # Walter configuration
        # Edit to taste — Walter reloads on next launch.
        # All fields are optional; missing values use the defaults shown here.

        [theme]
        background    = "#1e1e2e"
        foreground    = "#cdd6f4"
        accent        = "#cba6f7"
        border_radius = 12
        font          = "SF Pro"
        font_size     = 14

        [layout]
        width       = 780
        max_results = 8
        position    = "center"
        scale       = 1.0           # UI scale: 1.0 = default, 1.5 = 50% bigger

        [keybindings]
        open  = "Alt+Space"
        close = "Escape"
        """

        try? defaults.write(to: url, atomically: true, encoding: .utf8)
        print("Created default config at \(url.path)")
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            print("Config not found at \(configURL.path), using defaults")
            return
        }

        guard let content = try? String(contentsOf: configURL, encoding: .utf8) else {
            print("Failed to read config at \(configURL.path)")
            return
        }

        // Minimal TOML parser: handles [section] headers and key = value lines.
        // Supports string ("..."), integer, and float values.
        var currentSection = ""
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                currentSection = String(trimmed.dropFirst().dropLast())
                continue
            }

            let parts = trimmed.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespaces)
            var raw = parts[1].trimmingCharacters(in: .whitespaces)

            // Strip inline comments: `value # comment` → `value`
            // But not inside quoted strings.
            if !raw.hasPrefix("\"") {
                if let commentIdx = raw.firstIndex(of: "#") {
                    raw = String(raw[..<commentIdx]).trimmingCharacters(in: .whitespaces)
                }
            }
            let value = raw.trimmingCharacters(in: CharacterSet(charactersIn: "\""))

            switch (currentSection, key) {
            case ("theme", "background"):    theme.background = value
            case ("theme", "foreground"):    theme.foreground = value
            case ("theme", "accent"):        theme.accent = value
            case ("theme", "border_radius"): theme.borderRadius = Float(value) ?? theme.borderRadius
            case ("theme", "font"):          theme.font = value
            case ("theme", "font_size"):     theme.fontSize = Int(value) ?? theme.fontSize
            case ("layout", "width"):        layout.width = Int(value) ?? layout.width
            case ("layout", "max_results"):  layout.maxResults = Int(value) ?? layout.maxResults
            case ("layout", "position"):     layout.position = value
            case ("layout", "scale"):        layout.scale = Float(value) ?? layout.scale
            case ("keybindings", "open"):    keybindings.open = value
            case ("keybindings", "close"):   keybindings.close = value
            default: break
            }
        }

        print("Config loaded from \(configURL.path)")
    }
}
