# Walter — Windows Port Handoff

This document is a complete specification for building the Windows version of Walter. It describes every feature, behavior, UI detail, and platform mapping needed to produce a Windows app that matches the macOS version exactly.

The macOS source lives in `Walter/Sources/Walter/` (Swift + AppKit, ~3,000 lines across 18 files). The Windows version should be a separate project in a `WalterWin/` directory.

---

## Recommended Tech Stack

| Layer | macOS (current) | Windows (recommended) |
|---|---|---|
| Language | Swift | C# (.NET 8) or Rust |
| UI framework | AppKit (NSPanel) | WPF or WinUI 3 |
| Window style | Borderless NSPanel + NSVisualEffectView | Borderless Window + AcrylicBrush / Mica |
| Global hotkey | CGEventTap (suppresses key) | `RegisterHotKey` Win32 API |
| System tray | NSStatusItem | NotifyIcon (WPF) or system tray API |
| App indexing | FileManager + FSEvents | Scan Start Menu + `FileSystemWatcher` |
| Config | TOML parser (hand-rolled) | Same TOML format, same file location logic |
| Launch at login | SMAppService | Registry `HKCU\Software\Microsoft\Windows\CurrentVersion\Run` |

**My recommendation: C# + WPF** — it's the Windows equivalent of Swift + AppKit. Native, fast, full control over window chrome, and WPF's `AcrylicBrush` gives the frosted glass effect. Rust + egui or iced would work but you'll hit the same platform integration pain we had on macOS.

---

## Shared Config Format

Both platforms read the same `config.toml` format. On Windows, the config path should be:

```
%APPDATA%\walter\config.toml       (e.g. C:\Users\ekin\AppData\Roaming\walter\config.toml)
```

Frecency data:
```
%APPDATA%\walter\frecency.json
```

The TOML schema is identical:

```toml
[theme]
name          = "catppuccin-mocha"    # or any of the 21 built-in presets
background    = "#1e1e2e"
foreground    = "#cdd6f4"
accent        = "#cba6f7"
border_radius = 12
font          = "Segoe UI"            # Windows default instead of "SF Pro"
font_size     = 14
blur_material = "acrylic"             # acrylic | mica | none (Windows equivalents)

[layout]
width       = 780
max_results = 8
position    = "center"
scale       = 1.0
placeholder = "Search apps, calculate, convert..."

[keybindings]
open  = "Alt+Space"
close = "Escape"

[general]
editor = ""                           # empty = notepad.exe

[search]
engine               = "google"
show_system_commands = true
show_path            = true
# excluded_apps      = Cortana, Xbox
# app_dirs           = D:\Tools

[aliases]
# gh = "https://github.com"
```

---

## Feature-by-Feature Specification

### 1. App Indexing (`AppIndex.swift` → Windows equivalent)

**macOS behavior:** Scans these directories for `.app` bundles on startup:
- `/Applications`, `/Applications/Utilities`
- `/System/Applications`, `/System/Applications/Utilities`
- `/System/Library/CoreServices`
- `~/Applications` (recursive)
- Extra dirs from `app_dirs` config

**Windows equivalent:** Scan for `.lnk` (shortcuts) and `.exe` files in:
- `C:\ProgramData\Microsoft\Windows\Start Menu\Programs\` (all users)
- `%APPDATA%\Microsoft\Windows\Start Menu\Programs\` (current user)
- `%LOCALAPPDATA%\Programs\` (user-installed apps)
- Extra dirs from `app_dirs` config
- Parse `.lnk` files to resolve target path and extract display name
- Use `Icon.ExtractAssociatedIcon()` or `SHGetFileInfo` for app icons

**File watching:** macOS uses FSEvents. Windows equivalent: `FileSystemWatcher` on the Start Menu directories. Same 1-second latency for new app detection.

**Data model per app entry:**
```
name: String         # display name (from .lnk or exe metadata)
path: String         # full path to .lnk or .exe
nameLower: String    # pre-lowercased for matching
icon: Image          # extracted app icon, pre-sized to 64x64
```

---

### 2. Fuzzy Matching (`FuzzyMatch.swift` — portable, no platform deps)

The fuzzy match algorithm is pure logic, no platform APIs. Port directly:

**Algorithm:** Sequential character subsequence match with scoring.

**Scoring formula:**
| Signal | Points |
|---|---|
| Match at start of string | +15 |
| Match at word boundary (space, dash, camelCase) | +10 per char |
| Full acronym match (every query char is a boundary) | +20 |
| Longest consecutive run | +8 per char in run |
| Short target name bonus | +max(0, 50 - length) |
| Leading gap penalty | -2 per char before first match |
| Total gap penalty | -1 per gap char |

Minimum score: 0 (clamped).

---

### 3. Frecency Ranking (`FrecencyTracker.swift` — portable)

**Storage:** `frecency.json` in the config directory.

**Format:**
```json
{
  "C:\\Program Files\\Firefox\\firefox.exe": {
    "count": 47,
    "lastUsed": "2024-03-15T10:30:00Z"
  }
}
```

**Score formula:** `count * pow(0.5, daysSinceLastUse / 7.0)`

Half-life of 7 days: an app launched 10 times last month scores lower than an app launched 3 times today.

**Integration:** Frecency score is multiplied by 10 and added to the fuzzy match score for ranking.

---

### 4. Calculator (`Calculator.swift`)

**Detection:** Query contains at least one digit AND at least one operator (`+`, `-`, `*`, `/`, `%`, `^`, `(`, `)`).

**Evaluation:** macOS uses `NSExpression`. On Windows, use `DataTable.Compute()` (C#) or a simple expression parser. `x` and `X` are treated as `*` (multiply).

**Display:** First result row when detected. Icon: calculator symbol. Enter copies the answer to clipboard.

**Number formatting:** Integer results have no decimals. Decimal results show up to 10 significant digits. Comma separators for large numbers.

---

### 5. Currency & Unit Converter (`Converter.swift`)

**Currency — parse patterns:**
- `$100 in euro` → symbol prefix + amount + "in"/"to" + target
- `100 usd in try` → amount + currency name + "in"/"to" + target
- `€50 in` → show all popular targets as completion list

**Supported symbols:** `$`=USD, `€`=EUR, `£`=GBP, `¥`=JPY, `₺`=TRY, `₹`=INR, `₩`=KRW, `₽`=RUB, `₿`=BTC, `zł`=PLN

**Exchange rate API:** `https://open.er-api.com/v6/latest/USD` — free, no key. Fetch on startup, cache in memory for the session. All rates are relative to USD.

**Unit conversion categories and base units:**
| Category | Base unit | Units |
|---|---|---|
| Length | meters | km, m, cm, mm, mi, ft, in, yd |
| Weight | kg | kg, g, lb, oz |
| Temperature | celsius | C, F, K (non-linear conversion) |
| Data | bytes | TB, GB, MB, KB |

**Behavior:** When target is specified → single result. When target is omitted → show all compatible units as a completion list. Enter copies the value.

---

### 6. System Commands (`SystemCommands.swift`)

macOS commands mapped to Windows equivalents:

| Command | macOS | Windows |
|---|---|---|
| Lock Screen | `pmset displaysleepnow` | `rundll32 user32.dll,LockWorkStation` |
| Sleep | `pmset sleepnow` | `rundll32 powrprof.dll,SetSuspendState 0,1,0` |
| Restart | AppleScript System Events | `shutdown /r /t 0` (needs confirmation) |
| Shut Down | AppleScript System Events | `shutdown /s /t 0` (needs confirmation) |
| Empty Recycle Bin | AppleScript Finder | `SHEmptyRecycleBin` Win32 API (needs confirmation) |
| Toggle Dark Mode | AppleScript appearance prefs | Registry `AppsUseLightTheme` + broadcast |
| Open Config | Open in configured editor | Same logic, default to `notepad.exe` |
| Force Quit | Cmd+Opt Force Quit | Open Task Manager: `taskmgr.exe` |

**Confirmation:** Restart, Shut Down, and Empty Recycle Bin show a system dialog before executing.

---

### 7. Custom Aliases (`[aliases]` config section)

**Format in config:**
```toml
[aliases]
gh   = "https://github.com"           # opens URL in default browser
np   = "C:\\Windows\\notepad.exe"      # opens an app
ip   = "!curl -s ifconfig.me"          # runs shell command (prefix !)
```

**Matching:** Fuzzy match the alias key against the query. Show all matching aliases with their target as subtitle.

---

### 8. Web Search Fallback

Always appended as the last result row.

**Engines:**
| Config value | URL pattern |
|---|---|
| `google` | `https://www.google.com/search?q={query}` |
| `duckduckgo` | `https://duckduckgo.com/?q={query}` |
| `bing` | `https://www.bing.com/search?q={query}` |

**Icon:** Magnifying glass. **Action:** Open URL in default browser.

---

### 9. Global Hotkey (`HotkeyManager.swift`)

**macOS:** CGEventTap on a background thread with CFRunLoop. Suppresses the keystroke so it doesn't reach the active app.

**Windows:** `RegisterHotKey` Win32 API. This is much simpler than macOS:
```csharp
RegisterHotKey(hwnd, HOTKEY_ID, MOD_ALT, VK_SPACE);
```
The key is automatically suppressed (not passed to the active app). Process `WM_HOTKEY` messages in the message loop.

**Config parsing:** Same `parseBinding()` logic. Split on `+`, map modifier names to flags, map key names to virtual key codes.

**Hot-reload:** When config changes, call `UnregisterHotKey` then `RegisterHotKey` with the new combo.

---

### 10. System Tray (`StatusBarController.swift`)

**macOS:** NSStatusItem with custom icon, dropdown menu.

**Windows:** `NotifyIcon` (WPF) or Shell_NotifyIcon Win32 API.

**Menu items:**
1. Toggle Walter
2. ─── separator ───
3. Change Theme → submenu (same 21 themes, grouped Dark/Light, with "Spotlight (Default)" at top)
4. ─── separator ───
5. Launch at Login (toggle with checkmark)
6. Edit Config... (Ctrl+,)
7. ─── separator ───
8. Quit Walter

**Icon:** Same glove silhouette (`menubar_icon.png`), loaded as tray icon. On Windows, convert to `.ico` format (16x16 + 32x32 multi-resolution).

---

### 11. UI Layout & Styling

**Window type:** Borderless, always-on-top, no taskbar entry.

**Background:** Acrylic blur (Windows 10) or Mica (Windows 11). Fallback to solid color with slight transparency if acrylic is unavailable.

**Layout (all dimensions multiplied by `config.scale`):**

```
┌─────────────────────────────────────────┐
│  🔍  [Search field, 28pt light]          │  height: 72
├─────────────────────────────────────────┤  separator (1px, 16px inset)
│  [icon 40x40]  Title (15pt medium)      │  row height: 60
│                Subtitle (12pt regular)   │  row stride: 64
│  [icon 40x40]  Title                    │
│                Subtitle                  │
│  ...                                     │
└─────────────────────────────────────────┘
```

**Width:** `config.layout.width * scale`, clamped to 95% screen width.
**Height:** Input height + separator + (min(resultCount, maxResults) * rowStride), clamped to 90% screen height.
**Corner radius:** `config.theme.border_radius * scale`.

**Colors:**
- Background: `config.theme.background` at 92% opacity behind the blur
- Text: `config.theme.foreground`
- Search icon: foreground at 50% opacity
- Subtitle text: foreground at 60% opacity
- Selected row: `config.theme.accent` at 20% opacity, rounded corners
- Hover row: foreground at 5% opacity

**Scroll:** Result list scrolls when selection moves beyond visible area. ScrollViewer with hidden scrollbar.

**Position:** Centered on primary monitor, offset slightly above center. Saved/restored (top-left corner) across runs. Draggable by clicking anywhere on the background. Clamped to visible screen bounds.

---

### 12. Theme System

**21 built-in presets** (see `Themes.swift` for exact hex values):

**Dark:** spotlight, catppuccin-mocha, catppuccin-macchiato, catppuccin-frappe, nord, dracula, gruvbox, solarized-dark, rose-pine, rose-pine-moon, tokyo-night, one-dark, kanagawa, everforest, ayu-dark

**Light:** catppuccin-latte, solarized-light, github-light, rose-pine-dawn, ayu-light, everforest-light

**"spotlight" theme** uses transparent background (`#00000000`) to let the system blur show through uncolored.

**Theme picker flow (inside the launcher):**
1. User types "theme" → "Change Theme" appears as a result
2. Enter → switches to theme picker mode (placeholder changes to "Filter themes...")
3. Arrow keys navigate the list → each selection **live-previews** the theme (background, text, accent all change immediately)
4. Enter → confirms the theme, writes to config, closes launcher
5. Escape → reverts to the original theme, returns to normal search mode

**Live preview updates these properties directly (no window rebuild):**
- Window background color/opacity
- Search field text color
- Search icon tint
- Result row title/subtitle colors
- Selection accent color

---

### 13. Config Hot-Reload

**File watcher:** macOS uses `DispatchSource` on the file descriptor. Windows equivalent: `FileSystemWatcher` on the config directory, filter for `config.toml` changes.

**Atomic write handling:** Editors write atomically (write to temp file, rename). On macOS we re-create the watcher after each event because the fd goes stale. On Windows, `FileSystemWatcher` handles renames automatically — just debounce (300ms delay after last event).

**On reload:**
1. Reset all config values to defaults
2. Re-parse the TOML file
3. Apply theme preset if `name` is set
4. Fire `onChange` callback → rebuild the UI

**During theme preview:** Set a `suppressConfigRebuild` flag so the file watcher doesn't trigger a full panel rebuild while the user is browsing themes.

---

### 14. Keyboard Navigation

| Key | Action |
|---|---|
| Configured hotkey | Toggle launcher visibility |
| Escape | Close launcher (or exit theme picker if in that mode) |
| Enter | Launch selected result / confirm theme |
| Tab | Select next result |
| Shift+Tab | Select previous result |
| Down Arrow | Select next result |
| Up Arrow | Select previous result |
| Cmd+A (Ctrl+A on Windows) | Select all text in search field |
| Cmd+C/V/X (Ctrl+C/V/X) | Copy/Paste/Cut in search field |
| Cmd+, (Ctrl+, on Windows) | Open config file in editor |

---

### 15. Window Behavior

- **Show:** Capture the foreground window before activating Walter. Center on screen or restore last position.
- **Hide:** Close the window, restore focus to the previously active app. Reset search field and results.
- **App switch (Alt+Tab on Windows):** If Walter is visible, hide it.
- **Click outside:** Hide the launcher (detect `WM_ACTIVATE` with `WA_INACTIVE`).
- **Drag:** Window is draggable by clicking anywhere on the background. Search field and result rows still receive clicks normally.

---

### 16. Launch at Login

**macOS:** `SMAppService.mainApp.register()`

**Windows:** Add/remove registry key:
```
HKCU\Software\Microsoft\Windows\CurrentVersion\Run
  Walter = "C:\path\to\Walter.exe"
```

Toggle via tray menu item with checkmark state.

---

### 17. Editor Detection (for "Open Config")

**macOS:** Defaults to TextEdit. User can set `editor` in config.

**Windows:** Default to `notepad.exe`. User can set `editor` in config:
```toml
[general]
editor = "C:\\Program Files\\Microsoft VS Code\\Code.exe"
```

---

### 18. Distribution

**macOS:** Signed .app bundle + notarized DMG (see `dist/build-release.sh`).

**Windows:**
- Build as a single `.exe` (self-contained .NET publish or Rust release)
- Optional: MSIX package for Microsoft Store
- Optional: Inno Setup or WiX installer
- Code signing with an Authenticode certificate

---

## File Structure (recommended for Windows)

```
WalterWin/
  src/
    App/            Program.cs, TrayIcon setup, login item
    Config/         ConfigManager.cs, Themes.cs
    Hotkey/         HotkeyManager.cs (RegisterHotKey)
    Launcher/       AppIndex.cs, FuzzyMatch.cs, FrecencyTracker.cs,
                    Calculator.cs, Converter.cs, SystemCommands.cs,
                    LauncherEngine.cs
    UI/             LauncherWindow.xaml/.cs, ResultRow.xaml/.cs
  Resources/        Icons, assets
  config-example/   config.toml
```

---

## What Can Be Shared Across Platforms

These components are pure logic with zero platform dependencies — the algorithm and data structures are identical:

1. **FuzzyMatch** — scoring algorithm, boundary detection
2. **FrecencyTracker** — score formula, JSON format
3. **Calculator** — expression detection, number formatting
4. **Converter** — currency/unit parsing, conversion factors, API URL
5. **Themes** — all 21 preset hex values
6. **ConfigManager** — TOML parser logic (sections, key=value, inline comments)
7. **Config schema** — identical TOML format on both platforms

These require platform-specific implementations:

1. **AppIndex** — different directories, file types (.app vs .lnk/.exe), watcher API
2. **HotkeyManager** — CGEventTap vs RegisterHotKey
3. **SystemCommands** — completely different commands
4. **UI** — NSPanel/AppKit vs WPF/WinUI
5. **Tray** — NSStatusItem vs NotifyIcon
6. **LoginItem** — SMAppService vs Registry
7. **Editor detection** — different default paths
