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
        var mode: String = "list"     // "list" (Alfred-style) | "grid" (Spotlight-Tahoe-style)
    }

    struct Keybindings {
        var open: String = "Alt+Space"
        var close: String = "Escape"
    }

    struct Search {
        /// URL template (or named shorthand) used by the trailing
        /// web-search fallback row. Named `webSearch` rather than
        /// `engine` because the `[search]` section also configures
        /// app indexing and file indexing — `engine` was ambiguous.
        var webSearch: String = "google"
        var showSystemCommands: Bool = true
        var showPath: Bool = true
        var excludedApps: [String] = []
        var extraAppDirs: [String] = []
        /// Where to fetch URL-alias favicons from. Either a known shorthand
        /// (`google` / `duckduckgo` / `iconhorse`) or a full URL template
        /// containing `{host}`. Defaults to Google's S2 service at 128px,
        /// which is by far the highest-resolution free option.
        var faviconService: String = "google"
        /// Directories indexed for prefix-triggered file search (e.g. ``foo``).
        /// Empty disables file search entirely. The defaults live in the
        /// generated config file, NOT here — Walter must never start
        /// indexing a user's disk unless they've consented by listing the
        /// directories explicitly in `~/.config/walter/config.toml`. That
        /// way upgrading the app on an existing install never silently
        /// expands what Walter is allowed to read.
        var fileDirs: [String] = []
        /// Single character that activates file-search mode when typed at
        /// the start of the query. Defaults to backtick because it's easy
        /// to reach on US/UK layouts and isn't shadowed by anything else
        /// in the launcher's input vocabulary.
        var filePrefix: String = "`"
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
    var aliasNames: [String: String] = [:]   // optional display name per alias key
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
        aliasNames = [:]
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
# Walter configuration — reference file
#
# Changes apply live — just save. Comments start with '#'.
# Full docs: https://github.com/ekinertac/walter/blob/master/docs/config.md
#
# Sections (in order below):
#   [theme]        — colors, fonts, blur, corner radius
#   [layout]       — window size, position, scale, list-vs-grid mode
#   [keybindings]  — global hotkey + close key
#   [general]      — preferred text editor for "Open Config"
#   [search]       — web engine, favicon service, indexed app dirs
#   [aliases]      — user shortcuts, plain or parameterized

# ---------------------------------------------------------------------------
# Theme
# ---------------------------------------------------------------------------
# Built-in presets (set `name` to one of these to apply them):
#   spotlight (transparent, system vibrancy only)
#   Dark   — catppuccin-mocha, catppuccin-macchiato, catppuccin-frappe,
#            nord, dracula, gruvbox, solarized-dark, rose-pine,
#            rose-pine-moon, tokyo-night, one-dark, kanagawa,
#            everforest, ayu-dark
#   Light  — catppuccin-latte, solarized-light, rose-pine-dawn,
#            ayu-light, everforest-light, github-light
# Custom themes: drop a *.theme file under ~/.config/walter/themes/
# (auto-created with example.theme on first run) and reference it by
# filename (without extension) here.
[theme]
# name        = "catppuccin-mocha"   # presets override the colors below
background    = "#1e1e2e"            # CSS-style hex; "#00000000" = transparent
foreground    = "#cdd6f4"
accent        = "#cba6f7"
border_radius = 12                   # window corner radius in px
font          = "SF Pro"             # any installed font name, or "system"
font_size     = 14
# blur_material accepts: hudWindow | sidebar | popover | sheet | dark | light
blur_material = "hudWindow"

# ---------------------------------------------------------------------------
# Layout
# ---------------------------------------------------------------------------
[layout]
width       = 780                    # base width in pixels (before scaling)
max_results = 8                      # max visible result rows
position    = "center"               # center | top
scale       = 1.0                    # UI scale: 1.0 = default, 2.0 = double
placeholder = "Search apps, calculate, convert..."
# mode picks the result renderer:
#   list — Alfred/Raycast-style row list (default)
#   grid — Spotlight-Tahoe-style icon tiles (5 cols × 3 rows)
mode        = "list"

# ---------------------------------------------------------------------------
# Keybindings
# ---------------------------------------------------------------------------
# Modifiers: Alt/Option, Cmd/Command, Ctrl/Control, Shift
# Keys:      Space, Tab, Return, A-Z, 0-9, F1-F12, Up, Down, Left, Right
[keybindings]
open  = "Alt+Space"                  # global toggle
close = "Escape"                     # close (also unfocuses to previous app)

# ---------------------------------------------------------------------------
# General
# ---------------------------------------------------------------------------
# Preferred text editor for the "Open Config" action and Cmd+,.
# Leave empty to auto-detect — Walter checks (in order):
#   CotEditor, BBEdit, Sublime Text, VS Code, Cursor, Zed,
#   Zed Preview, Nova, MacVim, then TextEdit as a last resort.
[general]
# editor = "/Applications/CotEditor.app"

# ---------------------------------------------------------------------------
# Search
# ---------------------------------------------------------------------------
[search]
# Web search for the trailing fallback row. Either a built-in name
# (google | duckduckgo | bing) or a full URL template containing {query}:
#   web_search = "https://kagi.com/search?q={query}"
#   web_search = "https://html.duckduckgo.com/html/?q={query}"
#   web_search = "https://you.com/search?q={query}"
web_search           = "google"

show_system_commands = true          # Lock Screen, Sleep, Restart, ...
show_path            = true          # show file path in result subtitle

# Favicon service for URL aliases. Either a built-in shorthand or a URL
# template containing {host}:
#   "google"     — Google S2, up to 128px (best quality, default)
#   "duckduckgo" — DDG icon service, 32px (privacy-friendlier, low-res)
#   "iconhorse"  — icon.horse, returns site's largest icon
#   "https://api.faviconkit.com/{host}/144"   # custom template
# favicon_service     = "google"

# Hide specific apps from the index (comma-separated, name as displayed):
# excluded_apps      = Siri, News, Stocks

# Extra directories to scan for .app bundles (comma-separated):
# app_dirs           = /opt/myapps, ~/Tools

# Directories indexed for prefix-triggered file search. Type `<prefix>foo`
# to search filenames in these dirs only — outside of prefix mode the
# file index is invisible so apps stay first-class. Set `file_dirs = `
# (empty) to disable file search entirely.
file_dirs            = ~/Documents, ~/Desktop, ~/Downloads
# Single character that activates file-search mode (default: backtick).
# Pick something you don't normally type at the start of a query.
# file_prefix        = "`"

# ---------------------------------------------------------------------------
# Aliases
# ---------------------------------------------------------------------------
# Type the key to fire the value. Values can be:
#   - URLs        ("https://...")     — opened in default browser
#   - App / file  ("/Applications/..., /Users/...")   — opened via NSWorkspace
#   - Shell cmd   ("!curl -s example.com")            — run via /bin/sh -c
#
# Add {query} anywhere in the value to make the alias parameterized.
# Type "<key> <text>" and <text> is substituted before firing. URL
# aliases URL-encode the query; shell aliases pass it through raw.
#
# Flat form — alias key is the display name:
[aliases]
# gh    = "https://github.com"
# mail  = "/System/Applications/Mail.app"
# ip    = "!curl -s ifconfig.me"

# Sub-table form — adds a friendly display name. The launcher UI reads
# "YouTube → cat videos" instead of just "y → cat videos".
# [aliases.y]
# name = "YouTube"
# url  = "https://www.youtube.com/results?search_query={query}"
#
# [aliases.gh-s]
# name = "GitHub Search"
# url  = "https://github.com/search?q={query}"
#
# [aliases.?]
# name = "Ask Claude"
# url  = "https://claude.ai/new?q={query}"
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
        // When inside an `[aliases.<key>]` subsection, this holds <key> so
        // we know which alias the contained `name`/`url` keys belong to.
        var currentAliasKey: String? = nil

        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                let raw = String(trimmed.dropFirst().dropLast())
                if raw.hasPrefix("aliases.") {
                    // Sub-table form: `[aliases.foo]` declares alias key `foo`
                    // and switches to a section that accepts `name = ...`
                    // and `url = ...` (or the legacy `value`/`path`/`cmd`).
                    currentSection = "alias_subtable"
                    currentAliasKey = String(raw.dropFirst("aliases.".count))
                } else {
                    currentSection = raw
                    currentAliasKey = nil
                }
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
            case ("layout", "mode"):         layout.mode = value
            // Keybindings
            case ("keybindings", "open"):    keybindings.open = value
            case ("keybindings", "close"):   keybindings.close = value
            // Search
            // General
            case ("general", "editor"):      general.editor = value
            // Search
            case ("search", "web_search"):   search.webSearch = value
            case ("search", "favicon_service"): search.faviconService = value
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
            case ("search", "file_dirs"):
                // Path-only — `~` is expanded inside FileIndex itself so
                // the original config value can stay portable across users.
                let parsed = value.split(separator: ",").map {
                    $0.trimmingCharacters(in: .whitespaces)
                }
                // Empty list = disable file search; treat the literal
                // string "" the same way to give users an obvious off switch.
                search.fileDirs = parsed.filter { !$0.isEmpty }
            case ("search", "file_prefix"):
                // Take the first character — quietly ignore longer values
                // rather than failing the whole config load. A multi-char
                // prefix would clash with normal typing too easily.
                if let first = value.first { search.filePrefix = String(first) }
            // Aliases — flat form: `key = "value"`
            case ("aliases", _):             aliases[key] = value
            // Aliases — sub-table form: `[aliases.<key>]` then `name = ...` /
            // `url = ...`. The display name surfaces in the launcher UI so
            // a parameterized alias can read as e.g. "YouTube → cat videos"
            // instead of just "y → cat videos".
            case ("alias_subtable", "name"):
                if let k = currentAliasKey { aliasNames[k] = value }
            case ("alias_subtable", "url"),
                 ("alias_subtable", "value"),
                 ("alias_subtable", "path"),
                 ("alias_subtable", "cmd"):
                if let k = currentAliasKey { aliases[k] = value }
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

        // Update the favicon cache to whichever service the user picked
        // and warm it for every URL alias so parameterized aliases pick up
        // site icons without a startup-blocking fetch.
        FaviconCache.shared.serviceTemplate = FaviconCache.template(for: search.faviconService)
        let aliasHosts = aliases.values.compactMap { value -> String? in
            guard value.hasPrefix("http://") || value.hasPrefix("https://") else { return nil }
            return FaviconCache.hostname(for: value)
        }
        if !aliasHosts.isEmpty {
            FaviconCache.shared.prefetch(hostnames: aliasHosts)
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
