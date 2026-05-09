# Walter Configuration Reference

Walter reads its config from `~/.config/walter/config.toml`. The file is
auto-created on first launch with every option present and commented.
Saving the file applies changes live — no relaunch needed.

Themes can also be loaded from `~/.config/walter/themes/*.theme` (plain
text, see [Themes](#themes) below).

This document covers every setting Walter understands. Each section maps
1:1 to a `[section]` heading in `config.toml`.

---

## `[theme]`

Visual styling of the launcher window.

| Key             | Type   | Default       | Notes |
| --------------- | ------ | ------------- | ----- |
| `name`          | string | unset         | Built-in or user theme name. When set, overrides `background` / `foreground` / `accent`. |
| `background`    | hex    | `"#1e1e2e"`   | CSS-style. `"#00000000"` = transparent (system vibrancy only). |
| `foreground`    | hex    | `"#cdd6f4"`   | Text color. |
| `accent`        | hex    | `"#cba6f7"`   | Selection highlight + accent fills. |
| `border_radius` | int    | `12`          | Window corner radius in px. |
| `font`          | string | `"SF Pro"`    | Any installed font, or `"system"`. |
| `font_size`     | int    | `14`          | Search input font size at scale 1.0. |
| `blur_material` | string | `"hudWindow"` | One of `hudWindow`, `sidebar`, `popover`, `sheet`, `dark`, `light`. |

### Built-in theme presets

Set `name = "<preset>"` to apply one of these without specifying colors:

- **System:** `spotlight` (transparent, system vibrancy only)
- **Dark:** `catppuccin-mocha`, `catppuccin-macchiato`, `catppuccin-frappe`,
  `nord`, `dracula`, `gruvbox`, `solarized-dark`, `rose-pine`,
  `rose-pine-moon`, `tokyo-night`, `one-dark`, `kanagawa`, `everforest`,
  `ayu-dark`
- **Light:** `catppuccin-latte`, `solarized-light`, `rose-pine-dawn`,
  `ayu-light`, `everforest-light`, `github-light`

### Themes <a id="themes"></a>

Drop a plain-text file at `~/.config/walter/themes/<name>.theme`. The
filename (without extension) becomes the theme name. Format:

```
# my-cyberpunk.theme
background  #0a0a23
foreground  #00ffff
accent      #ff00ff
```

Three keys, whitespace-separated, `#` comments, `bg` / `fg` aliases work.
Saving any file in the themes directory triggers a hot-reload. Reference
your custom theme from `[theme]` like a built-in: `name = "my-cyberpunk"`.

---

## `[layout]`

Window geometry and result rendering.

| Key           | Type   | Default                                      | Notes |
| ------------- | ------ | -------------------------------------------- | ----- |
| `width`       | int    | `780`                                        | Base width in px before `scale` is applied. |
| `max_results` | int    | `8`                                          | Maximum visible result rows. Grid mode caps at 3 tile rows × 5 cols regardless. |
| `position`    | string | `"center"`                                   | `center` or `top`. Center vertically or pin to top edge. |
| `scale`       | float  | `1.0`                                        | UI scale factor — `2.0` doubles every dimension. |
| `placeholder` | string | `"Search apps, calculate, convert..."`       | Search field placeholder text. |
| `mode`        | string | `"list"`                                     | `list` (Alfred-style row list) or `grid` (Spotlight-Tahoe icon tiles). |

### List vs grid mode

- **`list`** — one row per result, icon + title + subtitle. Default.
  Best for mixed content (calculator, conversions, system commands).
- **`grid`** — 5-column tile sheet, large icons with a single label.
  Caps at 3 rows = 15 tiles. Computed answers (calculator, conversions)
  appear as a banner above the grid; the web-search fallback appears as
  a banner below.

Window position is remembered across launches and stays visually
anchored when `scale` changes between sessions.

---

## `[keybindings]`

Global hotkeys.

| Key     | Type   | Default       | Notes |
| ------- | ------ | ------------- | ----- |
| `open`  | string | `"Alt+Space"` | Toggle the launcher visibility. |
| `close` | string | `"Escape"`    | Hide the launcher and restore focus to the previous app. |

### Syntax

`<Modifier>+<Modifier>+<Key>`. Modifiers and keys are case-insensitive.

- **Modifiers:** `Alt` / `Option`, `Cmd` / `Command`, `Ctrl` / `Control`,
  `Shift`. Combine with `+`.
- **Keys:** `Space`, `Tab`, `Return`, `A`–`Z`, `0`–`9`, `F1`–`F12`,
  `Up`, `Down`, `Left`, `Right`.

Examples: `"Cmd+Shift+L"`, `"Ctrl+Alt+Space"`, `"F13"`.

### Accessibility permission

The global hotkey requires Accessibility access — Walter prompts on
first launch. Grant it under **System Settings → Privacy & Security →
Accessibility**. Without it the hotkey leaks the underlying key into
the active app instead of triggering Walter.

---

## `[general]`

Miscellaneous preferences.

| Key      | Type   | Default | Notes |
| -------- | ------ | ------- | ----- |
| `editor` | string | unset   | Path to the editor used by the **Open Config** action and `Cmd+,`. |

When `editor` is unset (or points at a missing path), Walter scans for
the first installed editor in this order:

1. `/Applications/CotEditor.app`
2. `/Applications/BBEdit.app`
3. `/Applications/Sublime Text.app`
4. `/Applications/Visual Studio Code.app`
5. `/Applications/Cursor.app`
6. `/Applications/Zed.app`
7. `/Applications/Zed Preview.app`
8. `/Applications/Nova.app`
9. `/Applications/MacVim.app`
10. `/System/Applications/TextEdit.app` (always present)

---

## `[search]`

Behavior of the search engine, app indexer, and trailing fallback row.

| Key                    | Type   | Default    | Notes |
| ---------------------- | ------ | ---------- | ----- |
| `web_search`           | string | `"google"` | Web search target for the trailing fallback row. Name or URL template (see below). |
| `show_system_commands` | bool   | `true`     | Surface Lock Screen / Sleep / Restart / etc. in results. |
| `show_path`            | bool   | `true`     | Show file path as result subtitle. Hide for a cleaner list. |
| `favicon_service`      | string | `"google"` | Where to fetch URL-alias favicons from (see below). |
| `excluded_apps`        | csv    | `""`       | Comma-separated app display names to hide from the index. |
| `app_dirs`             | csv    | `""`       | Extra directories to scan for `.app` bundles. `~` is expanded. |
| `file_dirs`            | csv    | unset (= disabled)                    | Directories indexed for prefix-triggered file search. Fresh installs get `~/Documents, ~/Desktop, ~/Downloads` in the generated config. |
| `file_prefix`          | string | `` "`" ``                             | Single character that activates file-search mode when typed first. |

### `web_search`

Built-in shorthands: `"google"`, `"duckduckgo"` (or `"ddg"`), `"bing"`.

For anything else, pass a URL template containing `{query}` where the
search term should land. Walter URL-encodes the query before substitution:

```toml
web_search = "https://kagi.com/search?q={query}"
web_search = "https://html.duckduckgo.com/html/?q={query}"
web_search = "https://you.com/search?q={query}"
```

The trailing fallback row reads "Search <name> for …" — for URL
templates the host name is shown.

### `favicon_service`

URL-alias rows show the target site's favicon. Walter caches images on
disk under `~/.config/walter/.cache/favicons/` and refetches them when
the service is changed.

Built-in shorthands:

- `"google"` — Google S2 at 128px. Highest resolution, recommended.
- `"duckduckgo"` (or `"ddg"`) — DuckDuckGo's icon service, 32px.
  Lower resolution but does not phone the user's alias hosts to Google.
- `"iconhorse"` — icon.horse. Returns the site's largest published icon.

Custom templates use `{host}`:

```toml
favicon_service = "https://api.faviconkit.com/{host}/144"
```

### `excluded_apps`

Hide an indexed app from search by adding its display name (case-insensitive):

```toml
excluded_apps = Siri, News, Stocks
```

For internal helper bundles that show up despite Walter's filters
(rare), this is the escape hatch.

### `app_dirs`

Extra directories to scan in addition to `/Applications`,
`/Applications/Utilities`, `/System/Applications`,
`/System/Applications/Utilities`, `/System/Library/CoreServices`,
`/System/Library/CoreServices/Applications`, `~/Applications`, and
`/Applications/MacPorts`.

```toml
app_dirs = /opt/myapps, ~/Tools
```

Newly added directories are watched live — adding or removing a `.app`
fires Walter's reindex within a second.

### `file_dirs`

Directories indexed for **prefix-triggered file search**. Type
`` `<query> `` (with a leading backtick) to search filenames in these
directories only. Outside of prefix mode the file index is invisible,
so apps stay the first-class result type and never get pushed down by
document hits. The prefix character is configurable via `file_prefix`.

```toml
file_dirs = ~/Documents, ~/Desktop, ~/Downloads
```

When Walter creates a config file for the first time, the three
user-content folders above are pre-filled — but if the key is absent
from your config, file search is **disabled**. Walter never indexes
disk content you didn't ask it to. Upgrading the app never silently
expands the index.

**Skip rules** — Walter never recurses into these subdirectory names:
`.git`, `.svn`, `.hg`, `node_modules`, `.build`, `build`, `dist`,
`target`, `Pods`, `.bundle`, `.cache`, `Library`. macOS bundle types
(`.app`, `.bundle`, `.framework`, `.kext`, `.plugin`, `.appex`,
`.rtfd`, `.photoslibrary`, `.musiclibrary`, `.tvlibrary`,
`.fcpbundle`, `.logicx`, `.garageband`) are treated as opaque leaves
so the user can find them by name without flooding the index with
their internals.

Hidden files (anything starting with `.`) are skipped. The whole index
is hard-capped at 50,000 entries; if you trip it Walter logs a warning
and you should narrow `file_dirs`. Listing `~/Code` or `~/` will hit
the cap quickly — point Walter at user-content folders instead.

Files are watched via FSEvents, so creating, deleting, or renaming a
file in any indexed directory updates Walter's catalog within ~2
seconds.

### `file_prefix`

Single character that activates file-search mode. Default is `` ` ``
(backtick). Pick any character you don't normally type at the start
of a query — apostrophe (`'`), colon (`:`), and slash (`/`) are
common alternatives.

```toml
file_prefix = "/"
```

If `file_dirs` is empty, hitting the prefix surfaces a one-row
shortcut that opens `config.toml` in your editor so you can fill in
the directories without leaving the launcher.

---

## `[aliases]`

User-defined shortcuts. Type the alias key in the launcher to fire it.

Values can be:

- **URL** (`http://…`, `https://…`) — opened in the default browser.
- **App / file path** — opened via `NSWorkspace`.
- **Shell command** — prefix with `!` to run via `/bin/sh -c`.

Add `{query}` anywhere in the value to make the alias parameterized:

```toml
[aliases]
ip = "!curl -s ifconfig.me"
y  = "https://www.youtube.com/results?search_query={query}"
gh-s = "https://github.com/search?q={query}"
```

Then type `y cat videos` — Walter substitutes `cat videos` for `{query}`,
URL-encodes it for URL aliases, and fires. Shell aliases receive the
text raw (so the alias author handles their own quoting).

When a parameterized alias matches, Walter suppresses fuzzy app/pane
matches for the same query — the user's intent is explicit. The
trailing web-search fallback still shows so escape is always one click
away.

### Display names (sub-table form)

The flat `key = "value"` form uses the key as the displayed result title.
For nicer labels, use the sub-table form:

```toml
[aliases.y]
name = "YouTube"
url  = "https://www.youtube.com/results?search_query={query}"

[aliases.gh-s]
name = "GitHub Search"
url  = "https://github.com/search?q={query}"

[aliases.?]
name = "Ask Claude"
url  = "https://claude.ai/new?q={query}"
```

The accepted value keys are `url`, `value`, `path`, and `cmd` — they all
populate the alias's value. `name` is always the optional display label.

Result rows then read **"YouTube → cat videos"** instead of
**"y → cat videos"**.

---

## File locations

| Path                                         | Purpose |
| -------------------------------------------- | ------- |
| `~/.config/walter/config.toml`               | Main config (this file). |
| `~/.config/walter/themes/`                   | User-defined `*.theme` files. Auto-created with example. |
| `~/.config/walter/.cache/favicons/`          | Cached favicons. Wiped automatically on `favicon_service` change. |
| `~/.config/walter/frecency.json`             | App launch counts + last-launched timestamps. Affects ranking. |

To start fresh, delete `~/.config/walter/` — the next launch recreates
defaults.
