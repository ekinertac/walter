# Walter
A lightweight, native macOS launcher for apps, System Settings, calculations,
unit conversions, and web searches. No accounts or telemetry.

> **Vibe-slop warning:** I've literally never built an iOS or macOS app, nor have I written a line of Swift code. I forked this from [ekinertac/walter](https://github.com/ekinertac/walter), which itself appears to be vibe-coded, then I used GPT 6.1 to improve performance and rip all outbound network requests and any functionality I didn't use. I also change the distribution model to be entirely "compile it yourself" based, as I am building this just to fill my own needs.

## Build and install
Requires macOS 13 or later and a Swift toolchain. Run the following command to compile/build and install to your `/Applications` directory.

```sh
make install
```

## Usage
Walter starts hidden. There is no dock icon nor tray icon. All config is hot-reloaded from `~/.config/walter/config.toml`.

- Press **Cmd+Space** (by default) to use
- With the pop-up open, hit `Cmd+q` to quit Walter.
- Press `Cmd+,` in the pop-up to see the config file location and reload instructions.

You should disable your Spotlight shortcut first, if you intend to keep `Cmd+Space` as the activation keybinding.

## Functionality
- Suggests apps under `/Applications` and `/System/Applications`
- Suggests entries from the System Settings pane
- Supports calculator operations
- Supports unit conversions (baked-in conversion factors, though; no outbound network requests to fetch anything)
- `change theme` to browse themes (press Return to save or Escape to cancel)
- All other results are treated as web searches to hand off to your default browser

## Configuration
- Edit `~/.config/walter/config.toml` to change the shortcut, theme, layout, or search engine. The file is created on first launch, and saved changes apply automatically.
- Add global app shortcuts with `[app_hotkeys]`, e.g. `"Cmd+Ctrl+t" = "/Applications/kitty.app"`. They launch/activate apps directly without opening the popup. See [configuration details](docs/config.md#app_hotkeys).
- Custom themes go in the sibling `themes/` directory.
- To start Walter at login, add it in **System Settings → General → Login Items**.
