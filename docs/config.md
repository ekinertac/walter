# Walter configuration reference

Default config: `~/.config/walter/config.toml`. `WALTER_CONFIG` overrides that
file's path. Themes always live in sibling `themes/`; the app seeds
`example.theme` if missing. Config/theme changes reload locally without showing
a hidden popup. Theme selection writes only the config file. There is no
`UserDefaults`, history, ranking database, favicon cache, or new storage scheme.

## Parser subset

Sections, `key = value`, quoted strings (straight or smart double quotes),
booleans, numbers, and comma-separated `excluded_apps` are supported. Whole-line
comments begin with `#`; inline comments after quoted values are supported.
This is not full TOML: no arbitrary arrays, escaping, or general nested tables.
Unknown/removed settings are ignored. Missing values use model defaults.
An invalid hotkey is reported rather than silently interpreted as Space.

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

| Key | Default | Behavior |
| --- | --- | --- |
| `width` | `780` | Points, clamped to 320–2400 and to 95% of the pointer screen's visible width. |
| `max_results` | `8` | 1–25 visible rows in list mode; grid also applies its own tile/row caps. |
| `placeholder` | `"Search apps, calculate, convert..."` | Empty-query prompt. |
| `mode` | `"list"` | `list` or `grid` (other values use list). |

Scale is fixed at its default. Position/geometry are not saved. The non-draggable
popup is horizontally centered on the screen containing the pointer, with its
top edge 30% down the visible area. It keeps that top anchor as results grow,
shifting upward only when needed to stay within the visible bottom edge. It
falls back to the main/first screen or a default rectangle when no screen is
available. Results are height-capped to that screen.

## `[keybindings]`

| Key | Default | Behavior |
| --- | --- | --- |
| `open` | `"Cmd+Space"` | Global launcher toggle, requires a modifier. |
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
working registrations. Startup may attempt the default `Cmd+Space` after
displaying a config/registration error; failure is also reported. Cmd+Space is
commonly assigned to Spotlight: change that shortcut yourself in System Settings
or choose a different Walter binding. Walter does not alter system shortcuts.
Existing config files retain their configured binding; the new default applies
when the setting or config file is absent.

Other local keys: Tab/Shift+Tab and arrows navigate results, Return activates,
Cmd+1…9 activates a numbered result, Cmd+C copies an answer/URL or revalidated
allowed app path (selected query text copies normally). Cmd+Return reveals only
a revalidated allowed app in Finder, never an arbitrary file. Grid horizontal
arrows navigate tiles; on computed/web banners they retain text editing.
There is no menu-bar or Dock icon. While the popup is active, Cmd+Q quits and
Cmd+, shows an alert with the actual config path and explains automatic reload.
These commands are local, not globally registered; they take precedence over a
matching configured close binding. The alert opens neither an editor nor Finder.
Dismissal restores input to the current popup only if it is still visible and
Walter is active. Hidden startup and hotkey-registration error alerts remain.

## `[search]`

| Key | Default | Behavior |
| --- | --- | --- |
| `web_search` | `"google"` | `google`, `duckduckgo`/`ddg`, `bing`, or an HTTP(S) URL template containing `{query}`. |
| `show_path` | `true` | Show an app's path in its result subtitle. |
| `excluded_apps` | empty | Comma-separated display names, case-insensitive. |

```toml
[search]
web_search = "https://kagi.com/search?q={query}"
show_path = true
excluded_apps = Example, Another App
```

Web search is the fallback. Query substitution is percent-encoded (including
parameter separators such as `&`); there are no suggestions, prefetches, URL
checks over the network, or remote icons. Invalid custom templates use the
local Google fallback. Only activation asks the browser to open the URL.

App discovery is fixed to `/Applications`, including ordinary subfolders but
excluding embedded apps/helpers and other package contents. Both lexical and
resolved paths must remain under the root; `/Applications-other` is not inside.
Internal symlinks are deduplicated; outside symlinks are excluded. Activation
revalidates so a stale/changed index cannot open an arbitrary path.

## `[aliases]`

Only HTTP(S) URLs and real allowed apps are accepted. Plain app aliases must
resolve to an `.app` bundle with `CFBundlePackageType = APPL` inside
`/Applications`, not inside another package. Arbitrary files/directories,
`file:` URLs, other schemes, parameterized app paths, and legacy `!` commands
(including leading-whitespace variants) are rejected, not reinterpreted.

```toml
[aliases]
gh = "https://github.com"
example = "/Applications/Example.app"

[aliases.y]
name = "YouTube"
url = "https://www.youtube.com/results?search_query={query}"
```

The key is fuzzy-matched. A URL template triggers on `<key> <text>`; encoded text
replaces `{query}` and suppresses unrelated fuzzy results. Web fallback remains.
URL aliases use the generic link icon; indexed apps retain native icons.
`name` is an optional display label; sub-table value keys are `url`, `value`,
and `path` (all subject to the same validation). Legacy `cmd` is ignored.

## Removed settings and legacy data

`layout.position`, `layout.scale`, `search.favicon_service`,
`search.show_system_commands`, `search.app_dirs`, `search.file_dirs`,
`search.file_prefix`, and `general.editor` have no effect. Walter does not
access legacy history/frecency JSON, favicon caches, or saved preferences.
It does not delete those files, clear permission grants, or unregister old
login items automatically. See [optional user cleanup](uninstall.md).
