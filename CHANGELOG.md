# Changelog

All notable changes to Walter are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.5.2] — 2026-05-24

### Fixed
- Grid mode (`layout.mode = "grid"`) silently ignored when the value carried
  an inline comment — the TOML parser kept everything after the closing quote,
  so `mode = "grid" # grid|list` was read as the literal `grid" # grid|list`.
  Quoted values now stop at the closing quote.
- Freshly-installed apps not appearing until Walter was restarted. The app
  index now re-scans on every launcher open as a safety net, covering cases
  where FSEvents missed the install (agent-process App Nap, bursty installers,
  fast `make`-style rebuild loops).
- Mac App Store iOS/iPad apps (e.g. Tapo) and modern asset-catalog apps never
  showing up. The internal-agent filter assumed a missing `CFBundleIconFile`
  meant a headless helper; it now also recognizes `CFBundleIconName`
  (asset-catalog icon) and `CFBundleIcons` / `CFBundleIcons~ipad` (iOS-on-Mac
  wrapped bundles) as evidence of a real, user-facing app.

## [1.5.1] — 2026-05-11

### Fixed
- Inline comments on quoted config values not being stripped, causing options
  like `mode` to silently mismatch. (Superseded by a more complete fix in
  1.5.2.)

## [1.5.0] — 2026-05-09

### Added
- **Prefix-triggered file search.** Type `` `<query> `` (backtick by default)
  to fuzzy-search filenames in user-listed directories only. Apps stay
  first-class outside of prefix mode. Configurable via `[search] file_dirs`
  and `[search] file_prefix`.
- Helpful setup guidance when the file prefix is hit with no `file_dirs`
  configured — a one-row shortcut that opens `config.toml` in your editor.
- Skip rules for the file index (`.git`, `node_modules`, `.build`, `Library`,
  etc.) and opaque-leaf handling for macOS bundle types. Hard cap of 50,000
  indexed entries.

### Changed
- **Breaking:** `[search] engine` renamed to `[search] web_search`. The
  `[search]` section now configures app indexing, file indexing, and the web
  fallback — `engine` was ambiguous. Update `engine = "…"` to
  `web_search = "…"`.
- File search is opt-in: existing installs index nothing unless `file_dirs` is
  set explicitly. Upgrading the app never silently expands what Walter reads.

## [1.4.0] — 2026-05-09

### Added
- **Parameterized aliases.** Add `{query}` anywhere in an alias value; typing
  `<key> <text>` substitutes `<text>` (URL-encoded for URLs, raw for shell).
  Fuzzy app/pane suggestions are suppressed while a parameterized alias matches.
- **Alias display names** via the `[aliases.<key>]` sub-table form
  (`name` + `url`).
- **Hi-res favicons for URL aliases**, disk-cached, configurable via
  `[search] favicon_service` (Google S2 default, DuckDuckGo, icon.horse, or a
  custom `{host}` template).
- **Configurable web search engine** — `[search] engine` accepts any URL
  template containing `{query}` on top of the `google`/`duckduckgo`/`bing`
  shorthands.
- **Editor auto-detection** for "Open Config" / Cmd+, — CotEditor, BBEdit,
  Sublime Text, VS Code, Cursor, Zed, Nova, MacVim, then TextEdit.
- Full configuration reference in [`docs/config.md`](docs/config.md); the
  generated default `config.toml` now documents every option inline.

## [1.3.0] — 2026-05-09

### Added
- **Spotlight-Tahoe grid layout** (`[layout] mode = "grid"`) — a 5-column icon
  tile sheet capped at 3 rows. Calculator/conversion answers render as a top
  banner; the web-search fallback as a bottom banner. 2-D arrow-key navigation.

### Changed
- All searchable results (apps, system commands, System Settings panes,
  aliases, theme entry) now compete in a single fuzzy + frecency scored pool
  instead of fixed per-category ordering. Computed answers stay pinned to the
  top, web search to the bottom.

### Fixed
- Prefix matches now beat frecency-boosted scattered matches — typing "to"
  surfaces Tolaria above a heavily-used Stremio. Prefix match adds a 60-point
  bonus; the frecency boost is capped at 40 so it tunes ranking without
  overruling a clearly better match.

## [1.2.0] — 2026-05-07

### Added
- **System Settings pane search** — type "bluetooth", "display", "wi-fi", etc.
  to open the matching pane via `x-apple.systempreferences:`. 40 panes covered.
- **User-defined themes** — drop `*.theme` files in `~/.config/walter/themes/`,
  hot-reloaded on save.
- First-party app allowlist for built-ins that ship without a
  `CFBundleIconFile` (System Settings, Mail, Safari, Notes, ~50 others).

### Fixed
- Safari and other Cryptex-symlinked apps under `/System/Cryptexes/…` no longer
  silently dropped (their `/Applications` symlink is flagged hidden).
- Internal helper bundles (RegisterPluginIMApp, NowPlayingTouchUI, etc.) no
  longer pollute results.
- Duplicate entries for the same app at multiple system paths (Tips,
  Screenshot, Siri, Contacts) collapsed by bundle identifier.
- Launcher position stays visually anchored when `layout.scale` changes between
  sessions.

## [1.1.0] — 2026-05-05

### Added
- Initial public release: native macOS launcher (Swift + AppKit).
- Fuzzy app search with frecency ranking, FSEvents-watched index.
- Inline calculator, currency conversion, unit conversion.
- System commands (lock, sleep, restart, …) with confirmation on destructive
  actions.
- Custom aliases (URLs, app paths, shell commands).
- 21 built-in themes with live in-launcher preview.
- Configurable global hotkey with CGEventTap keystroke suppression.
- Configurable web search fallback.
- Menu bar agent, launch-at-login, scalable UI, frosted-glass blur,
  hot-reloaded TOML config.

[1.5.2]: https://github.com/ekinertac/walter/releases/tag/v1.5.2
[1.5.1]: https://github.com/ekinertac/walter/releases/tag/v1.5.1
[1.5.0]: https://github.com/ekinertac/walter/releases/tag/v1.5.0
[1.4.0]: https://github.com/ekinertac/walter/releases/tag/v1.4.0
[1.3.0]: https://github.com/ekinertac/walter/releases/tag/v1.3.0
[1.2.0]: https://github.com/ekinertac/walter/releases/tag/v1.2.0
[1.1.0]: https://github.com/ekinertac/walter/releases/tag/v1.1.0
