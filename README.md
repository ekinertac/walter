<p align="center">
  <img src="walter-icon.png" width="128" height="128" alt="Walter icon">
</p>

<h1 align="center">Walter</h1>

<p align="center">A fast, native macOS launcher with a highly customisable UI.</p>

Built with Swift + AppKit. No Electron, no WebView, no Rust+Iced compromises — just native macOS APIs that work.

## Features

- **Instant app search** — indexes all installed apps on startup (~50ms), discovers new installs within 1 second via FSEvents
- **Fuzzy matching** — type "vsc" to find Visual Studio Code, "ff" for Firefox, "calc" for Calculator
- **Frecency ranking** — apps you use often and recently bubble to the top
- **Inline calculator** — type `128*3+15` and get the answer instantly, Enter copies to clipboard
- **Currency conversion** — `$100 in euro`, `500 try in usd` with live exchange rates
- **Unit conversion** — `10 km in miles`, `72 f in c`, `1 tb in gb`
- **Web search fallback** — no results? last row offers Google search
- **Global hotkey** — Alt+Space from any app (uses NSEvent monitor, not CGEventTap)
- **Menu bar agent** — lives in the tray, no Dock icon
- **Scalable UI** — single `scale` factor in config resizes everything (try `scale = 2.0`)
- **Frosted glass** — NSVisualEffectView blur, system accent colors, dark/light mode support
- **Draggable** — drag the window anywhere, position is remembered across restarts
- **TOML config** — `~/.config/walter/config.toml`, auto-created on first run

## Install

```bash
git clone https://github.com/ekinertac/walter.git
cd walter
make run
```

Requires macOS 13+ and Swift 5.9+.

## Configuration

Config lives at `~/.config/walter/config.toml` (auto-created on first run):

```toml
[theme]
background    = "#1e1e2e"
foreground    = "#cdd6f4"
accent        = "#cba6f7"
border_radius = 12

[layout]
width       = 780
max_results = 8
scale       = 1.0       # 1.0 = default, 2.0 = double size

[keybindings]
open  = "Alt+Space"
close = "Escape"
```

## Usage

| Action | Key |
|---|---|
| Open/close launcher | Alt+Space |
| Navigate results | Tab / Shift+Tab / Arrow keys |
| Launch / copy result | Enter |
| Close | Escape |
| Quit | Tray menu > Quit Walter |
| Launch at login | Tray menu > Launch at Login |

## Architecture

```
Walter/Sources/Walter/
  App/          WalterApp (entry), AppDelegate, LoginItemManager
  Hotkey/       NSEvent global+local monitors
  Tray/         NSStatusItem menu bar controller
  UI/           KeyablePanel, LauncherPanelController, ResultsListView
  Launcher/     AppIndex (FSEvents), FuzzyMatch, FrecencyTracker,
                Calculator, Converter (currency+units), LauncherEngine
  Config/       TOML config loader
```

## License

MIT
