// ConfigManager.swift — TOML config with FSEvents hot-reload
//
// Reads ~/.config/walter/config.toml, creates it on first run,
// watches for changes, and re-parses + fires onChange on save.

import Foundation

class ConfigManager {

    struct Theme {
        var name: String?                       // built-in theme name (overrides individual colors)
        var background: String = "#1e1e2e"
        var foreground: String = "#cdd6f4"
        var accent: String = "#cba6f7"
        var borderRadius: Float = 12.0
        var font: String = "SF Pro"
        var fontSize: Int = 14
        var blurMaterial: String = "hudWindow"   // hudWindow | sidebar | popover | sheet | dark | light
    }

    struct Layout {
        var width: Int = 780
        var maxResults: Int = 8
        var position: String = "center"
        var scale: Float = 1.0
        var placeholder: String = "Search apps, calculate, convert..."
    }

    struct Keybindings {
        var open: String = "Alt+Space"
        var close: String = "Escape"
    }

    struct Search {
        var engine: String = "google"
        var showSystemCommands: Bool = true
        var showPath: Bool = true
        var excludedApps: [String] = []
        var extraAppDirs: [String] = []
    }

    struct General {
        var editor: String = ""                 // path to preferred text editor, empty = auto-detect
    }

    var theme = Theme()
    var layout = Layout()
    var keybindings = Keybindings()
    var general = General()
    var search = Search()
    var aliases: [String: String] = [:]
    var userThemes: [String: ThemePreset] = [:]   // loaded from ~/.config/walter/themes/*.theme

    /// Built-in + user themes, with user winning on name collision.
    var allThemes: [String: ThemePreset] {
        var merged = builtinThemes
        for (k, v) in userThemes { merged[k] = v }
        return merged
    }

    var onChange: (() -> Void)?
    private var fileMonitor: DispatchSourceFileSystemObject?
    private var themesMonitor: DispatchSourceFileSystemObject?

    func s(_ base: CGFloat) -> CGFloat {
        base * CGFloat(layout.scale)
    }

    init() {
        ensureConfigExists()
        ensureUserThemesDirExists()
        load()
        startWatching()
        startWatchingThemes()
    }

    deinit {
        stopWatching()
        stopWatchingThemes()
    }

    var configURL: URL {
        if let env = ProcessInfo.processInfo.environment["WALTER_CONFIG"] {
            return URL(fileURLWithPath: env)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/walter/config.toml")
    }

    /// Directory containing user-defined `*.theme` files.
    var userThemesDir: URL {
        configURL.deletingLastPathComponent().appendingPathComponent("themes")
    }

    func reload() {
        theme = Theme()
        layout = Layout()
        keybindings = Keybindings()
        general = General()
        search = Search()
        aliases = [:]
        userThemes = [:]
        load()
        print("Config hot-reloaded")
        DispatchQueue.main.async { [weak self] in self?.onChange?() }
    }

    // MARK: - First-run default config

    private func ensureConfigExists() {
        let url = configURL
        guard !FileManager.default.fileExists(atPath: url.path) else { return }

        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let defaults = """
# Walter configuration
# Changes are applied live — just save the file.

[theme]
# Built-in themes: spotlight, catppuccin-mocha, catppuccin-latte,
#   catppuccin-macchiato, catppuccin-frappe, nord, dracula, gruvbox,
#   solarized-dark, solarized-light, rose-pine, rose-pine-moon,
#   rose-pine-dawn, tokyo-night, one-dark, kanagawa, everforest,
#   everforest-light, ayu-dark, ayu-light, github-light
# Set a theme name to use its presets (individual colors below are ignored):
# name          = "catppuccin-mocha"
background    = "#1e1e2e"
foreground    = "#cdd6f4"
accent        = "#cba6f7"
border_radius = 12
font          = "SF Pro"       # any installed font name, or "system"
font_size     = 14
blur_material = "hudWindow"    # hudWindow | sidebar | popover | sheet

[layout]
width       = 780              # base width in pixels (before scaling)
max_results = 8                # max visible result rows
position    = "center"         # center | top
scale       = 1.0              # UI scale: 1.0 = default, 2.0 = double
placeholder = "Search apps, calculate, convert..."

[keybindings]
# Modifiers: Alt/Option, Cmd/Command, Ctrl/Control, Shift
# Keys: Space, Tab, Return, A-Z, 0-9, F1-F12, Up, Down, Left, Right
open  = "Alt+Space"
close = "Escape"

[general]
# Preferred text editor for "Open Config" command.
# Leave empty to auto-detect (VS Code, Zed, Sublime Text, etc.)
# editor = "/Applications/Visual Studio Code.app"

[search]
engine               = "google"    # google | duckduckgo | bing
show_system_commands = true
show_path            = true        # show file path in result subtitle
# excluded_apps      = Siri, News, Stocks
# Extra directories to scan for .app bundles (comma-separated):
# app_dirs           = /opt/myapps, ~/Tools

# Custom aliases — type the key to open the value.
# Values can be URLs, app paths, or shell commands (prefix with !)
[aliases]
# gh    = "https://github.com"
# mail  = "/System/Applications/Mail.app"
# ip    = "!curl -s ifconfig.me"
# yt    = "https://youtube.com"
"""

        try? defaults.write(to: url, atomically: true, encoding: .utf8)
        print("Created default config at \(url.path)")
    }

    /// Creates ~/.config/walter/themes/ on first run and seeds it with a
    /// commented example file so users have something to copy from.
    private func ensureUserThemesDirExists() {
        let dir = userThemesDir
        let fm = FileManager.default
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)

        let example = dir.appendingPathComponent("example.theme")
        guard !fm.fileExists(atPath: example.path) else { return }

        let body = """
        # example.theme — sample custom theme for Walter
        #
        # Drop more *.theme files in this directory to add themes.
        # The filename (without extension) is the theme's name; reference
        # it from config.toml with `name = "example"` under [theme].
        #
        # Each theme needs three keys: background, foreground, accent.
        # Values are CSS-style hex colors. Aliases `bg` / `fg` also work.
        # Lines starting with `#` are comments.

        background  #1a1a2e
        foreground  #eaeaea
        accent      #ff6b6b
        """
        try? body.write(to: example, atomically: true, encoding: .utf8)
        print("Seeded user themes dir at \(dir.path)")
    }

    // MARK: - TOML parser

    private func load() {
        // Pick up any user-defined themes before parsing config so that
        // `name = "..."` lookups resolve against the merged map.
        userThemes = loadUserThemes(from: userThemesDir)

        guard FileManager.default.fileExists(atPath: configURL.path),
              let content = try? String(contentsOf: configURL, encoding: .utf8) else {
            print("Config not found or unreadable, using defaults")
            return
        }

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

            if !raw.hasPrefix("\"") {
                if let commentIdx = raw.firstIndex(of: "#") {
                    raw = String(raw[..<commentIdx]).trimmingCharacters(in: .whitespaces)
                }
            }
            let value = raw.trimmingCharacters(in: CharacterSet(charactersIn: "\""))

            switch (currentSection, key) {
            // Theme
            case ("theme", "name"):          theme.name = value
            case ("theme", "background"):    theme.background = value
            case ("theme", "foreground"):    theme.foreground = value
            case ("theme", "accent"):        theme.accent = value
            case ("theme", "border_radius"): theme.borderRadius = Float(value) ?? theme.borderRadius
            case ("theme", "font"):          theme.font = value
            case ("theme", "font_size"):     theme.fontSize = Int(value) ?? theme.fontSize
            case ("theme", "blur_material"): theme.blurMaterial = value
            // Layout
            case ("layout", "width"):        layout.width = Int(value) ?? layout.width
            case ("layout", "max_results"):  layout.maxResults = Int(value) ?? layout.maxResults
            case ("layout", "position"):     layout.position = value
            case ("layout", "scale"):        layout.scale = Float(value) ?? layout.scale
            case ("layout", "placeholder"):  layout.placeholder = value
            // Keybindings
            case ("keybindings", "open"):    keybindings.open = value
            case ("keybindings", "close"):   keybindings.close = value
            // Search
            // General
            case ("general", "editor"):      general.editor = value
            // Search
            case ("search", "engine"):       search.engine = value
            case ("search", "show_system_commands"): search.showSystemCommands = (value == "true")
            case ("search", "show_path"):    search.showPath = (value == "true")
            case ("search", "excluded_apps"):
                search.excludedApps = value.split(separator: ",").map {
                    $0.trimmingCharacters(in: .whitespaces)
                }
            case ("search", "app_dirs"):
                let home = FileManager.default.homeDirectoryForCurrentUser.path
                search.extraAppDirs = value.split(separator: ",").map {
                    $0.trimmingCharacters(in: .whitespaces)
                        .replacingOccurrences(of: "~", with: home)
                }
            // Aliases
            case ("aliases", _):             aliases[key] = value
            default: break
            }
        }

        // Apply theme preset by name — built-in or user-defined under
        // ~/.config/walter/themes/. Individual colors below it are ignored.
        if let themeName = theme.name?.lowercased(),
           let preset = allThemes[themeName] {
            theme.background = preset.background
            theme.foreground = preset.foreground
            theme.accent = preset.accent
            print("Theme applied: \(themeName)")
        }

        print("Config loaded from \(configURL.path)")
    }

    // MARK: - File watcher
    //
    // Uses DispatchSource to watch the config file. Atomic writes (used by
    // most editors and our own write(to:atomically:)) replace the file via
    // rename, which invalidates the old file descriptor. So after each event
    // we tear down and re-create the watcher on the new file.

    private func startWatching() {
        stopWatching()

        let path = configURL.path
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else {
            print("ConfigManager: can't watch \(path)")
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete, .attrib],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            guard let self else { return }
            // Stop old watcher (fd is now stale after atomic rename)
            self.stopWatching()
            // Delay briefly — the new file may not be fully in place yet
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.reload()
                // Re-create watcher on the new file
                self.startWatching()
            }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        fileMonitor = source
    }

    private func stopWatching() {
        fileMonitor?.cancel()
        fileMonitor = nil
    }

    // MARK: - Themes directory watcher
    //
    // Watches ~/.config/walter/themes/ so that adding, editing, or removing
    // a *.theme file triggers a reload without the user also having to
    // touch config.toml. Uses the same DispatchSource fd-watcher pattern as
    // the config-file monitor; the fd is on the directory itself, and
    // .write fires whenever its contents change.

    private func startWatchingThemes() {
        stopWatchingThemes()

        let path = userThemesDir.path
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else {
            print("ConfigManager: can't watch \(path)")
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete, .attrib],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            guard let self else { return }
            self.stopWatchingThemes()
            // Debounce — editors often emit multiple events per save.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.reload()
                self.startWatchingThemes()
            }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        themesMonitor = source
    }

    private func stopWatchingThemes() {
        themesMonitor?.cancel()
        themesMonitor = nil
    }
}
