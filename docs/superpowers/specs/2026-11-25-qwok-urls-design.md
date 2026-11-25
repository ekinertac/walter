# Open qwok app URLs from Walter

Status: approved 2026-11-25

## Intent

Open a local dev app by name from Walter. Type `qwok b2`, press Tab to complete, press Enter to open the URL in the browser. It works like the `repo` shortcut.

## Decided by Ekin

- Integrate qwok in order to open URLs, similar to `repo`.
- Enter only opens the URL, also when the app is stopped (option B).
- The data source is the `qwok list` table (option 1).

## Behavior

- `qwok ` lists all apps with a URL in alphabetical order, at most 25. `qwok b2` filters them with the existing fuzzy match, best match first.
- The row title is the app name. The subtitle is the URL.
- Tab fills `qwok <name>` into the field. Enter opens the URL. Cmd+C copies the URL.
- The bare word `qwok` without a space is a normal search, as for `repo`.
- No app has a URL, or no match: one row gives the reason. Enter does nothing on it.
- qwok not installed: one row gives `brew install ekinertac/tap/qwok`, Enter copies it.
- qwok fails: one row shows its stderr.

## Design

- New file `Walter/Sources/Walter/Launcher/QwokIndex.swift`, with a pure parser, pure ranking, and a loader with the same state shape as `GitHubIndex`.
- The parser splits each line on whitespace. It keeps a row only when the second field is `web` or `app` and the fourth field starts with `http://` or `https://`. All other lines are skipped: the header, rows without a URL, the "no apps registered" message.
- The loader runs `qwok list` on a background queue. It looks for qwok in `/opt/homebrew/bin` and `/usr/local/bin`, and puts both at the front of PATH for the child process. Without this, qwok cannot find portless and prints a different URL.
- The list is kept in memory only. Opening the Walter panel marks it as old, and the first `qwok ` keystroke fetches it again. The old list stays visible during the fetch. `onChange` runs only when the result changed.
- `LauncherEngine.search` checks the prefix on the raw query, next to the GitHub check. The GitHub check goes first if both prefixes are equal.
- New setting `[search] qwok_prefix`, default `"qwok"`, empty turns it off. Same parsing as `github_prefix`.

## Non-goals

- No start, stop, restart or logs.
- No running/stopped status in the rows. qwok's status can be wrong for an app started outside qwok.
- No rows for apps without a URL. Changed during implementation: since qwok 8856bc7 (2026-11-25 21:11) a `type=app` project can have a URL, and then it is listed.
- No change in qwok.

## Known limits

- If the app or the portless proxy is down, the browser shows an error page. This is the accepted result of option B.
- If portless is installed somewhere else (for example under nvm), qwok prints its fallback URL, which can have the wrong port.

## Approaches

1. **Read the `qwok list` table (picked).** No qwok release, one call gives name, type and URL. Depends on the column order, which is stable because published qwok output is treated as API.
2. **Add `qwok list --json`.** Cleanest contract, but needs Go code, a release, a tap update and the new qwok on every Mac.
3. **Read `registry.toml` and `.qwok.toml`, run `qwok open`.** Immediate names, but depends on private files, needs TOML parsing, and has no URL to show or copy.

## Tests and docs

- Unit tests: the parser (normal table, `app` rows, empty-registry message, malformed lines, stopped row without a port), the ranking, the `qwok_prefix` config.
- Update `docs/config.md`, the README table, `CHANGELOG.md` and the default config template.

## Left to the builder

Icon, exact error texts, and whether the `Process` helper in `GitHubIndex` is shared or repeated. It is the second use, so repeat it unless sharing is simpler.
