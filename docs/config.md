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

| Key                 | Type   | Default       | Notes |
| ------------------- | ------ | ------------- | ----- |
| `name`              | string | unset         | Built-in or user theme name. When set, overrides `background` / `foreground` / `accent`. |
| `background`        | hex    | `"#1e1e2e"`   | CSS-style. `"#00000000"` = transparent (system vibrancy only). |
| `foreground`        | hex    | `"#cdd6f4"`   | Primary text color. |
| `accent`            | hex    | `"#cba6f7"`   | Accent fills; default source for the selection highlight. |
| `selection`         | hex    | unset         | Selection highlight fill. Defaults to `accent` at 25% opacity. |
| `subtitle`          | hex    | unset         | Subtitle / secondary text. Defaults to `foreground` at 60% opacity. |
| `border`            | hex    | unset         | Hairline window border. Off when unset. |
| `placeholder_color` | hex    | unset         | Search-field placeholder text. Defaults to `foreground` at 50% opacity. |
| `border_radius`     | int    | `12`          | Window corner radius in px. |
| `font`              | string | `"SF Pro"`    | Any installed font, or `"system"`. |
| `font_size`         | int    | `14`          | Search input font size at scale 1.0. |
| `font_weight`       | string | `"medium"`    | Result-title weight: `light`, `regular`, `medium`, `semibold`, `bold`. |
| `blur_material`     | string | `"hudWindow"` | One of `hudWindow`, `sidebar`, `popover`, `sheet`, `dark`, `light`. |

The optional `selection`, `subtitle`, `border`, and `placeholder_color`
keys all derive sensible values from the core three colors when omitted,
so existing themes render identically without specifying them.

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
# optional — derive from the above when omitted:
selection   #1a1a44
subtitle    #6699aa
border      #00ffff
```

Core three keys are required; `selection` / `subtitle` / `border` are
optional. Whitespace-separated, `#` comments, `bg` / `fg` aliases work.
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
  Best for mixed content (calculator, conversions, Settings panes).
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

### In-launcher keys (fixed)

Beyond the configurable `open` / `close` hotkeys, these keys are fixed
while the launcher is open:

| Key | Action |
| --- | ------ |
| `Enter` | Launch / open / copy the selected result |
| `Cmd+Enter` | Reveal the selected result in Finder (apps; falls back to the normal action for everything else) |
| `Cmd+1` … `Cmd+9` | Jump to and activate the Nth visible result (hint shown on each row) |
| `Cmd+C` | Copy the selected result's value — revalidated app path, alias/Settings URL, or computed answer. When text is selected in the search field, defers to normal text copy. |
| `Cmd+V` | Paste into the search field |
| `Tab` / `Shift+Tab` | Next / previous result |
| `↑` / `↓` | Move selection (list and grid) |
| `←` / `→` | Move the text cursor; in grid mode, move between tiles when a tile is selected |
| `Esc` | Close the launcher (or exit theme-preview) |

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
| `show_path`            | bool   | `true`     | Show file path as result subtitle. Hide for a cleaner list. |
| `excluded_apps`        | csv    | `""`       | Comma-separated app display names to hide from the index. |

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

### `excluded_apps`

Hide an indexed app from search by adding its display name (case-insensitive):

```toml
excluded_apps = Siri, News, Stocks
```

For internal helper bundles that show up despite Walter's filters
(rare), this is the escape hatch.

Apps are discovered only under `/Applications`, including ordinary subfolders.
Both lexical and resolved paths must stay inside that root. Embedded helpers,
packages and escaping symlinks are excluded. App activation, path copying and
Finder reveal revalidate the same boundary. Extra app roots are not supported.

---

## `[aliases]`

User-defined shortcuts. Type the alias key in the launcher to fire it.

Values can be:

- **URL** (`http://…`, `https://…`) — opened in the default browser.
- **App path** — a real app whose resolved path remains inside `/Applications`.
  Arbitrary files, outside-root apps, and parameterized app paths are rejected.

Add `{query}` to an HTTP(S) URL to make the alias parameterized:

```toml
[aliases]
y  = "https://www.youtube.com/results?search_query={query}"
gh-s = "https://github.com/search?q={query}"
```

Then type `y cat videos` — Walter substitutes `cat videos` for `{query}`,
URL-encodes it for URL aliases, and fires.

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

The accepted value keys are `url`, `value`, and `path` — they all
populate the alias's value. `name` is always the optional display label.
Legacy `!` commands (including whitespace-prefixed values) and `cmd` fields
are rejected, not interpreted as paths or URLs.

Result rows then read **"YouTube → cat videos"** instead of
**"y → cat videos"**.

---

## File locations

| Path                                         | Purpose |
| -------------------------------------------- | ------- |
| `~/.config/walter/config.toml`               | Main config (this file). |
| `~/.config/walter/themes/`                   | User-defined `*.theme` files. Auto-created with example. |

Walter does not record queries or app usage. Results use ordinary fuzzy
matching, with alphabetical title ordering for equal scores; Up/Down navigate
results rather than recalling queries.

Legacy `history.json` and `frecency.json` files are no longer read or written.
Existing personal copies are left untouched; no automatic cleanup is performed.
