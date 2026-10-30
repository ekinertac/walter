# Agent operating restrictions

These restrictions apply to all agent work in this repository, including
operations performed through tools, scripts, subprocesses, APIs, or delegated
agents. Do not bypass them through an alternative interface.

## No write-style Git operations

Use Git only for read-only inspection, such as `git status`, `git diff`,
`git log`, and `git show`.

Do not perform Git operations that modify the working tree, index, repository
metadata, refs, configuration, or remote state. This includes staging,
committing, amending, switching or creating branches, checking out files,
resetting, cleaning, stashing, merging, rebasing, cherry-picking, reverting,
tagging, fetching, pulling, pushing, initializing repositories, and modifying
Git configuration or worktrees. Do not modify Git internals directly or use
another tool to perform these operations.

Ordinary source-file edits are allowed; this restriction prohibits write-style
Git operations, not the coding task itself.

## No GitHub CLI

Do not invoke the `gh` CLI for any purpose, including read-only queries,
authentication, or commands wrapped in scripts or aliases.

## No background services or unattended workflows

Do not start background jobs, daemons, services, development servers, watchers,
scheduled jobs, browser automation, headless browsers, or unattended workflows.
Do not trigger these processes remotely or through another tool.

Foreground compilation/build commands and automated tests are allowed when they
terminate on completion, do not publish artifacts, and do not start prohibited
services. Tests must be offline, isolate filesystem/preferences state, and must
not launch Walter, external apps, or permission prompts. Inspect test setup and
constructor side effects before running unfamiliar suites; fix unsafe tests or
ask before proceeding. Test-scoped file watchers are allowed only when needed
to test hot reload and reliably stopped before the test process exits.

## Do not launch Walter

Do not launch Walter, including through `make run`, `swift run`, `open`, a test,
or direct executable invocation. GUI/runtime validation is a stop-and-ask case:
provide manual steps for the user or request a narrowly scoped exception.

## No publishing artifacts

Do not publish, upload, deploy, release, or otherwise distribute artifacts
anywhere, whether publicly or privately. This includes package registries,
container registries, release assets, hosting services, cloud storage, remote
artifact stores, and local publishing destinations. Do not trigger a workflow
or use another tool to publish on your behalf.

Creating local build outputs as part of an allowed compilation is permitted;
publishing or distributing those outputs is not.

## Stop and ask

If a task requires any prohibited operation, or it is unclear whether a command
would perform one, stop before executing it. Explain the required operation and
why it is needed, then ask the user to perform it themselves or explicitly
authorize a narrowly scoped exception. Do not treat the original task request,
tool availability, or a suggested command as authorization. Continue only with
work that does not require the prohibited operation while awaiting the user's
response.

# Repository context

## Purpose and behavior

Walter is a personal, native macOS launcher built as a self-contained local
`.app`. Building and running Walter are offline-only: no accounts, telemetry,
remote assets, rate APIs, update checks, external package dependencies,
certificates, notarization, or release infrastructure. Ad-hoc local signing is
part of app packaging.

Allowed results/actions are apps under `/Applications`, System Settings panes,
calculator answers, offline unit conversions, themes, and explicitly activated
web-search/URL-alias handoffs. Constructing a URL locally and asking the default
browser to open it is allowed; Walter itself must not fetch internet resources.
External apps may independently use the network.

Do not add file search, arbitrary file launching, shell aliases, system-command
execution, query history, usage tracking/frecency, remote favicons, or
`UserDefaults` persistence. Config access is an explicit filesystem exception.
The popup uses fixed default scale, cannot be dragged, and is centered within
the visible area of the screen containing the pointer. Division is fractional,
not integer-truncated.

Global shortcuts use Carbon/HIToolbox registration without Accessibility or
Input Monitoring permission. Launch at login is managed by the user through
macOS Login Items, not app registration APIs or a Walter setting. Start hidden
on every launch, including manual and login launches; show the popup only on
the launcher hotkey. Config reload must not reveal a hidden popup. Explicit
hotkey-registration error alerts remain appropriate. Themes and config hot
reload are supported. Walter has no Dock/menu-bar icon; popup-local Cmd+Q quits,
and Cmd+, explains the config location without opening an editor.

## Network boundary

- No network I/O initiated by Walter, directly or through subprocesses/helpers:
  no HTTP requests, DNS lookups, sockets, connectivity probes, downloads, or
  background retries. Offline means no attempts, not merely graceful failure
  without a connection. Do not add opt-in network features.
- The sole external-URL exception is a user-activated browser handoff for web
  search or a URL alias. No prefetching, URL validation over the network,
  previews, favicon loading, or search suggestions. Typing, startup, config
  reload, and theme selection must remain local.
- Bundle required assets and data locally. Builds and tests must work without
  network access once the macOS/Swift toolchain is installed; no dependency or
  fixture downloads. Tests must use local fixtures/mocks, never live endpoints.
- Review network behavior in initializers, dependencies, scripts, and helpers,
  not just obvious request calls. Report any violation found. Static inspection
  alone is not proof of zero runtime traffic; describe validation accurately.

This boundary governs Walter and its build/test code, not unrelated macOS or
external-app activity. Do not use network-backed paths in tests; user-selected
config/theme paths may have filesystem behavior outside Walter's control.

## Documentation alignment

This file describes the intended codebase contract, not task status. If code or
other documentation disagrees with it, highlight the discrepancy to the user:
it may be a code defect or stale guidance. Do not silently assume either is
correct or expand an assigned task to resolve every discrepancy. The user's
prompt and supporting documents define the work being delegated.

## Build and resources

- Swift + AppKit; macOS 13+. SwiftPM manifest: `Walter/Package.swift`, with no
  external dependencies. Tests use Swift Testing (`import Testing`), requiring
  a toolchain that supplies it beyond the manifest's Swift tools 5.9 minimum.
- `make build` runs `dist/build-release.sh`: foreground release compilation,
  local app packaging, and ad-hoc signing. No DMG, notarization, or publishing.
- Output: `dist/build/Walter.app`; intermediates: `Walter/.build/`. Do not edit
  generated outputs. Compile without packaging using
  `swift build --package-path Walter` (optionally `-c release`).
- Bundle metadata: `dist/Info.plist`; identifier: `local.personal.walter`.
  `LSUIElement` supports no-Dock operation; it does not itself remove a status item.
- Preserve `App/WalterResources.swift` and the embedded `Walter_Walter.bundle`
  under `Contents/Resources/`. Installed resources must not depend on the checkout.
- `make run` launches Walter and is prohibited without an exception.
  `make install` copies to `/Applications` and refuses overwrite; leave installing
  and replacing the user's copy to the user unless explicitly authorized.
- Inherited README/changelog/Windows material can be stale. Inspect the current
  manifest, Makefile, scripts, and source for actual behavior; report mismatches.

## Source orientation

Paths are relative to `Walter/Sources/Walter/`:

- `App/`: hidden startup, subsystem lifetime, and resources.
- `Hotkey/`: binding parsing, global shortcut registration and dispatch.
- `UI/`: popup lifecycle, keyboard handling, list/grid rendering, theme preview.
- `Launcher/`: query routing, fuzzy matching, allowed-app indexing/launching,
  calculator, offline unit conversion, and System Settings links.
- `Config/`: config models/parser, generated defaults, hot reload, themes.

Keep per-keystroke search responsive; avoid blocking I/O. Computed answers lead,
fuzzy-ranked results follow, and web search is the fallback. Consider both list
and grid layouts. Keep global shortcut lifetime independent of panel rebuilds
and theme previews.

## Config, state, and tests

- Default config: `~/.config/walter/config.toml`; `WALTER_CONFIG` overrides it.
  User themes are in the sibling `themes/` directory; an example theme is seeded.
- Parser: hand-written TOML subset in `Config/ConfigManager.swift`. Update model
  defaults, parser, generated config, tests, and `docs/config.md` together.
- Never modify/delete personal config, legacy history/caches/preferences, login
  registrations, or permission records as a debugging/reset shortcut. Do not
  edit macOS permission databases. Use temporary test fixtures and injected
  dependencies; do not assume `WALTER_CONFIG` isolates every legacy store.
- Tests: `Walter/Tests/WalterTests/`; run safe foreground suites with `make test`
  or `swift test --package-path Walter`. Remove tests for removed functionality;
  do not preserve obsolete behavior just to satisfy them. Mock OS integration
  rather than invoking browser/app launches, login registration, or prompts.
- Report checks actually performed. For GUI behavior, give the user focused
  manual verification steps; do not launch Walter yourself.
