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

| Key | Default | Behavior |
| --- | --- | --- |
| `name` | unset | Built-in or user theme name, case-insensitive. Overrides core colors. |
| `background` | `"#1e1e2e"` | Window background; transparent `#00000000` gives vibrancy-only appearance. |
| `foreground` | `"#cdd6f4"` | Main text color. |
| `accent` | `"#cba6f7"` | Accent/selection base color. |
| `selection` | unset | Otherwise accent at 25% opacity. |
| `subtitle` | unset | Otherwise foreground at 60% opacity. |
| `border` | unset | Optional border color. |
| `placeholder_color` | unset | Otherwise foreground at 50% opacity. |
| `border_radius` | `12` | Corner radius, clamped to 0–100. |
| `font` | `"SF Pro"` | Font name, `system`, or empty; fallback to system font. |
| `font_size` | `14` | Legacy parsed compatibility field; currently does not change rendered sizes. |
| `font_weight` | `"medium"` | Result-title weight: ultralight, thin, light, regular/normal, medium, semibold, bold, heavy, black. |
| `blur_material` | `"hudWindow"` | `sidebar`, `popover`, `sheet`; other values use hudWindow. |

The search input uses a fixed 28-point base font and shrinks to a readable
14-point minimum for long queries. Result fonts are fixed independently of the
legacy `font_size` field. This inherited mismatch is recorded in the baseline
audit, not a promise that `font_size` changes the UI.

Built-in names:

- System: `spotlight`.
- Dark: `catppuccin-mocha`, `catppuccin-macchiato`, `catppuccin-frappe`, `nord`,
  `dracula`, `gruvbox`, `solarized-dark`, `rose-pine`, `rose-pine-moon`,
  `tokyo-night`, `one-dark`, `kanagawa`, `everforest`, `ayu-dark`.
- Light: `catppuccin-latte`, `solarized-light`, `github-light`, `rose-pine-dawn`,
  `ayu-light`, `everforest-light`.

Custom themes are local whitespace-separated files:

```text
# ~/.config/walter/themes/example.theme
background #1a1a2e
foreground #eaeaea
accent #ff6b6b
selection #45475a
subtitle #6c7086
border #313244
```

Three core colors are required; optional palette colors are supported.
`bg`/`fg` are aliases for background/foreground. Lines starting with `#` are
comments; a hex color's `#` is data. Filenames without `.theme` are theme names.
User themes win name collisions with built-ins. Preview does not persist;
Return saves the selected theme, Escape cancels.

## `[layout]`

Window geometry and result rendering.

| Key           | Type   | Default                                      | Notes |
| ------------- | ------ | -------------------------------------------- | ----- |
| `width`       | int    | `780`                                        | Width in points, clamped to 320–2400 and capped to 95% of the pointer screen's visible width. |
| `max_results` | int    | `8`                                          | Clamped to 1–25 visible rows. Grid mode also applies its tile/row caps. |
| `placeholder` | string | `"Search apps, calculate, convert..."`       | Search field placeholder text. |
| `mode`        | string | `"list"`                                     | `list` (Alfred-style row list) or `grid` (Spotlight-Tahoe icon tiles). |

### List vs grid mode

- **`list`** — one row per result, icon + title + subtitle. Default.
  Best for mixed content (calculator, conversions, Settings panes).
- **`grid`** — 5-column tile sheet, large icons with a single label.
  Caps at 3 rows = 15 tiles. Computed answers (calculator, conversions)
  appear as a banner above the grid; the web-search fallback appears as
  a banner below.

Scale is fixed at its default. Position/geometry are not saved. The non-draggable
popup is horizontally centered on the screen containing the pointer, with its
top edge 30% down the visible area. It keeps that top anchor as results grow,
shifting upward only when needed to stay within the visible bottom edge. It
falls back to the main/first screen or a default rectangle when no screen is
available. Results are height-capped to that screen.

## `[keybindings]`

| Key | Default | Behavior |
| --- | --- | --- |
| `open` | `"Alt+Space"` | Global launcher toggle, requires a modifier. |
| `close` | `"Escape"` | Popup-local dismissal/cancel binding. Escape also remains normal cancel. |

Modifiers: `Alt`/`Option`/`Opt`, `Cmd`/`Command`/`Super`, `Ctrl`/`Control`, `Shift`.
Keys: A–Z, 0–9, F1–F12, Space, Tab, Return/Enter, Escape/Esc,
Delete/Backspace, Up, Down, Left, Right. Key codes follow the macOS virtual-key
layout. Binding names are case-insensitive; spaces surrounding `+` are ignored.
Unknown keys, multiple keys, repeated modifiers, missing keys, and empty `+`
components are rejected. There is no fallback from an unknown key to Space.

Carbon registrations work globally, including when Walter is active, without
Accessibility or Input Monitoring access. Multiple registration IDs/action
mappings are supported internally; **new app-hotkey config is deferred**.
Duplicate names/normalized bindings (including launcher conflicts) are rejected.
Reload stages new registrations before releasing old handles; failure retains
working registrations. Startup may attempt the explicit default `Alt+Space`
after displaying a config/registration error; failure is also reported. Walter
does not alter Spotlight or other system shortcuts.

Other local keys: Tab/Shift+Tab and arrows navigate results, Return activates,
Cmd+1…9 activates a numbered result, Cmd+C copies an answer/URL or revalidated
allowed app path (selected query text copies normally). Cmd+Return reveals only
a revalidated allowed app in Finder, never an arbitrary file. Grid horizontal
arrows navigate tiles; on computed/web banners they retain text editing.
The existing tray has Quit; popup-local Cmd+Q/Cmd+, behavior is deferred.

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

## Startup and login

Walter starts hidden on every launch, including manual and login launches. Only
the launcher hotkey shows/toggles the popup; config reload does not reveal a
hidden popup. The retained tray offers themes, About, and Quit, not a launcher
toggle or login setting. Explicit hotkey-registration error alerts may appear.

To start Walter at login, add it yourself in macOS System Settings → General →
Login Items. Walter does not register, query, or unregister login items.
Existing registrations are left untouched; manage them in System Settings.
