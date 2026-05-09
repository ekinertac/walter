<p align="center">
  <img src="walter-icon.png" width="128" height="128" alt="Walter icon">
</p>

<h1 align="center">Walter</h1>

<p align="center">A fast, native macOS launcher with a highly customisable UI.<br>Built with Swift + AppKit. No Electron, no WebView — just native macOS APIs.</p>

## Features

- **Instant app search** — indexes all installed apps on startup (~50ms), discovers new installs within 1 second via FSEvents file watching
- **Fuzzy matching** — type "vsc" to find Visual Studio Code, "ff" for Firefox, "calc" for Calculator
- **Frecency ranking** — apps you use often and recently bubble to the top, persisted across launches
- **Inline calculator** — type `128*3+15` and get the answer instantly, Enter copies to clipboard
- **Currency conversion** — `$100 in euro`, `500 try in usd` with live exchange rates from open.er-api.com
- **Unit conversion** — `10 km in miles`, `72 f in c`, `1 tb in gb` with completion list
- **System commands** — type "lock", "sleep", "restart", "dark mode", "empty trash", "force quit" — destructive actions prompt for confirmation
- **Custom aliases** — define shortcuts in config: `gh = "https://github.com"`, `ip = "!curl -s ifconfig.me"`. Add `{query}` for parameterized aliases (`y cat videos` opens YouTube search)
- **System Settings panes** — type "bluetooth", "display", "wi-fi" — opens the matching pane directly via `x-apple.systempreferences:` URL scheme. 40 panes covered
- **20+ built-in themes** — Catppuccin, Nord, Dracula, Tokyo Night, Gruvbox, Rose Pine, and more — browse and preview live from within the launcher
- **User-defined themes** — drop plain-text `*.theme` files into `~/.config/walter/themes/`, hot-reloaded on save
- **Two layouts** — Alfred-style row list (default) or Spotlight-Tahoe icon grid (5×3 tiles), pick via `[layout] mode`
- **Hi-res favicons for URL aliases** — fetched from Google S2 (configurable: DuckDuckGo, icon.horse, custom)
- **Configurable hotkey** — Alt+Space by default, change to any combo in config (e.g. `Cmd+Space`, `Ctrl+Shift+K`)
- **Keystroke suppression** — CGEventTap consumes the hotkey so it doesn't leak into the active app
- **Web search fallback** — always the last result, configurable engine (Google, DuckDuckGo, Bing)
- **Menu bar agent** — lives in the tray with your custom icon, no Dock icon
- **Scalable UI** — single `scale` factor resizes everything (try `scale = 3.0` for a huge launcher)
- **Frosted glass** — NSVisualEffectView blur with configurable material, adapts to dark/light mode
- **Draggable** — drag the window anywhere, position remembered across restarts
- **Hot-reload config** — edit `~/.config/walter/config.toml`, save, and changes apply instantly
- **Launch at login** — toggle from the tray menu (uses SMAppService)
- **Open Config** — Cmd+, or type "open config" to edit settings in your preferred editor

## Install

```bash
git clone https://github.com/ekinertac/walter.git
cd walter
make run
```

Requires macOS 13+ and Swift 5.9+.

### Build a distributable DMG

```bash
make dist          # build + sign + notarize + DMG
make dist-quick    # build + sign + DMG (skip notarization, for testing)
```

Requires a Developer ID Application certificate and `notarytool` keychain profile.

## Configuration

Config lives at `~/.config/walter/config.toml` — auto-created on first
run with every option present and commented, hot-reloaded on save.

**See [docs/config.md](docs/config.md) for the full reference** — every
key, default, accepted value, and example for theme presets, hotkey
syntax, alias variants (flat + sub-table form), search-engine /
favicon-service templates, and file locations.

Quick taste:

```toml
[theme]
name          = "catppuccin-mocha"     # or set background/foreground/accent yourself
border_radius = 12
font          = "SF Pro"

[layout]
width       = 780
scale       = 1.0                      # 1.0 = default, 3.0 = huge
mode        = "list"                   # list | grid (Spotlight-Tahoe tiles)

[keybindings]
open  = "Alt+Space"                    # any combo: Alt+Tab, Cmd+Space, Ctrl+Shift+K

[search]
engine          = "google"             # or any "https://...{query}..." template
favicon_service = "google"             # google | duckduckgo | iconhorse | custom

[aliases.y]                            # named, parameterized alias
name = "YouTube"
url  = "https://www.youtube.com/results?search_query={query}"
```

## Usage

| Action | Key |
|---|---|
| Open/close launcher | Alt+Space (configurable) |
| Navigate results | Tab / Shift+Tab / Arrow keys |
| Launch / copy result | Enter |
| Close | Escape |
| Open config | Cmd+, |
| Change theme | Type "theme", browse with arrows, Enter to confirm, Esc to revert |
| Quit | Tray menu > Quit Walter |
| Launch at login | Tray menu > Launch at Login |

## Architecture

```
Walter/Sources/Walter/
  App/          WalterApp (entry), AppDelegate, LoginItemManager
  Hotkey/       CGEventTap (suppresses key) + NSEvent local monitor
  Tray/         NSStatusItem, theme picker submenu
  UI/           KeyablePanel, LauncherPanelController,
                ResultsListView, ResultsGridView (5x3 Spotlight-Tahoe tiles)
  Launcher/     AppIndex (FSEvents), PrefPaneIndex (System Settings panes),
                FaviconCache (Google S2 / DDG / icon.horse), FuzzyMatch,
                FrecencyTracker, Calculator, Converter, SystemCommands,
                LauncherEngine
  Config/       ConfigManager (TOML parser + hot-reload),
                Themes (20+ presets), UserThemes (~/.config/walter/themes/)
docs/
  config.md           Full configuration reference
dist/
  build-release.sh    Sign + notarize + DMG automation
  Info.plist          App bundle metadata (LSUIElement, etc.)
  Walter.entitlements Hardened runtime entitlements
```

## License

MIT
