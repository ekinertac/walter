<p align="center">
  <img src="walter-icon.png" width="128" height="128" alt="Walter icon">
</p>

<h1 align="center">Walter</h1>

<p align="center">
  A native macOS launcher that respects your time and your machine.<br>
  No Electron. No accounts. No plugin marketplace. Just Swift, AppKit, and a TOML file.
</p>

<p align="center">
  <a href="https://github.com/ekinertac/walter/releases/latest"><img src="https://img.shields.io/github/v/release/ekinertac/walter?style=flat-square" alt="Latest release"></a>
  <img src="https://img.shields.io/badge/macOS-13%2B-blue?style=flat-square" alt="macOS 13+">
  <img src="https://img.shields.io/badge/Swift-5.9%2B-orange?style=flat-square" alt="Swift 5.9+">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-green?style=flat-square" alt="MIT license"></a>
</p>

## What Walter is

A keystroke-fast, single-window launcher. You hit `Alt+Space`, you type a few letters, you launch an app or copy a number. That's it. Walter does the four things you actually use a launcher for and stops there:

1. Launch apps and System Settings panes
2. Compute things — calculator, unit conversions, currency conversions
3. Run user-defined shortcuts — URLs, files, shell commands, parameterized templates
4. Bounce a query out to the web

It boots in tens of milliseconds, draws with native AppKit, and reloads its config the instant you save the file. Every option is a line in a TOML file you can read, diff, and version-control. There is no telemetry, no sign-in, no upsell.

## What Walter is not

- **Not a platform.** No plugin marketplace, no extension API, no third-party JS sandbox to keep up with. The whole codebase is ~3,000 lines of Swift you can read in an afternoon.
- **Not Electron.** No Chromium runtime, no Node bundle, no 200 MB DMG. The release build is around **8 MB**.
- **Not a SaaS.** Nothing phones home. Nothing requires an account. AI chat, snippet libraries, clipboard managers, window tilers — those belong in dedicated apps you already trust. Walter doesn't try to absorb them.
- **Not opinionated about your editor, search engine, browser, or theme.** Every one of those is a config knob.

## Principles

- **Focused.** A launcher is a launcher. New features earn their place by removing friction from one of the four things above; otherwise they don't ship.
- **Native.** Pure Swift + AppKit. CGEventTap for the global hotkey. NSVisualEffectView for the blur. FSEvents for the index. No webview, no abstraction layer pretending to be a window.
- **Fast.** ~50 ms cold-start app indexing for ~200 apps. Zero-allocation fuzzy matching on every keystroke. Newly-installed apps appear in the index within ~1 s of `mv`-ing them into `/Applications`.
- **Developer-friendly.** Plain-text config (`~/.config/walter/config.toml`), plain-text themes (`*.theme`), hot-reloaded on save. Aliases support `{query}` substitution. Search engine and favicon service accept URL templates. The full reference is in [docs/config.md](docs/config.md).

## Features

**Search**
- Fuzzy match across all installed apps with prefix-bias and frecency ranking — `vsc` → Visual Studio Code, `to` → Tolaria
- System Settings pane direct-open — `bluetooth`, `display`, `wi-fi`, etc. (40 panes covered)
- System commands — `lock`, `sleep`, `restart`, `dark mode`, `empty trash`, `force quit` (destructive ones prompt)
- Web search fallback — Google by default, any URL template welcome (`https://kagi.com/search?q={query}`)

**Compute**
- Calculator — type `128*3+15` and Enter copies the answer
- Currency conversion — `$100 in euro`, `500 try in usd`, live rates
- Unit conversion — `10 km in miles`, `72 f in c`, `1 tb in gb`

**Aliases**
- Plain — `gh = "https://github.com"`, `ip = "!curl -s ifconfig.me"`, `mail = "/System/Applications/Mail.app"`
- Parameterized — add `{query}` to make `y cat videos` open `youtube.com/results?search_query=cat%20videos`
- Sub-table form for friendly display names — `[aliases.y] name = "YouTube"`
- Hi-res site favicons (Google S2, DuckDuckGo, icon.horse, or any `{host}` template)

**Look and feel**
- Two layouts — Alfred-style row list, or Spotlight-Tahoe icon grid (5×3 tiles)
- 21 built-in themes (Catppuccin, Nord, Dracula, Tokyo Night, Gruvbox, Rose Pine, …) — browse and live-preview from inside the launcher
- User-defined themes — drop a `*.theme` file in `~/.config/walter/themes/`, save, see it appear
- Frosted-glass blur, dark/light aware, configurable material
- Single `scale` factor resizes the whole launcher — `scale = 3.0` for a huge one
- Draggable, position remembered across launches and across `scale` changes

**Niceties**
- Configurable global hotkey — Alt+Space by default, swap for anything (`Cmd+Space`, `Ctrl+Shift+K`)
- Hotkey is consumed by a CGEventTap so it never leaks into the active app
- Hot-reload config + themes — save and apply, no relaunch
- Menu bar agent (no Dock icon), launch-at-login toggle
- Cmd+, opens the config in CotEditor / BBEdit / Sublime / VS Code / Cursor / Zed / Nova / TextEdit (auto-detected, override-able)

## Install

**From a release** — grab the latest DMG from the [releases page](https://github.com/ekinertac/walter/releases/latest), drag `Walter.app` to `/Applications`, launch, grant Accessibility when prompted (the global hotkey needs it).

**From source** — Walter builds with the Xcode toolchain that ships with macOS 13+; no extra dependencies.

```bash
git clone https://github.com/ekinertac/walter.git
cd walter
make run             # debug build, launches Walter
make release         # release build only
make reinstall       # quit, rebuild, install to /Applications, relaunch
```

Requires macOS 13 (Ventura) or later and Swift 5.9+.

### Build a distributable DMG

```bash
make dist          # build + sign + notarize + DMG
make dist-quick    # build + sign + DMG (skip notarization, for testing)
```

Requires a Developer ID Application certificate and a `notarytool` keychain profile.

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

## Contributing

Walter stays small on purpose. PRs that fix bugs, sharpen what's already
there, or improve the build are very welcome. PRs that add new
top-level features will get a friendly skeptical read against the four
principles above before they merge — please open an issue first to
discuss anything substantial. The bar to clear is "this removes
friction from launching apps, computing answers, running shortcuts, or
escaping to the web". Snippet libraries, clipboard managers, AI chat,
and similar belong in dedicated apps and won't be added here.

## License

MIT
