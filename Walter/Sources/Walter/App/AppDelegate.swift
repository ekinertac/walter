// AppDelegate.swift — Wires together all subsystems on launch
//
// Owns the top-level objects that must live for the process lifetime:
//   - StatusBarController (tray icon + menu)
//   - HotkeyManager (global Alt+Space listener)
//   - LauncherPanelController (the floating search window)
//   - ConfigManager (TOML config loading + hot-reload)
//
// Walter starts hidden on every launch; only the launcher hotkey toggles the popup.

import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusBar: StatusBarController!
    private var hotkeys: HotkeyManager?
    private var panel: LauncherPanelController!
    private var config: ConfigManager!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Set the app icon (used in About dialog, Cmd+Tab if ever shown, etc.)
        if let iconURL = WalterResources.bundle.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = icon
        }

        // Load config (falls back to defaults if file is missing)
        config = ConfigManager()

        // Create the launcher panel (hidden initially)
        panel = LauncherPanelController(config: config)

        // Menu bar icon with Quit action
        statusBar = StatusBarController(config: config)

        do {
            hotkeys = HotkeyManager(backend: try CarbonHotkeyBackend())
            configureHotkeys()
        } catch { showHotkeyError(error) }

        setupEditMenu()

        // Hot-reload: when config.toml is saved, rebuild the panel with new values.
        // Full teardown+rebuild is simpler and more reliable than patching every
        // property individually — the panel is cheap to construct.
        config.onChange = { [weak self] in
            guard let self else { return }

            // Registrations survive theme preview and panel replacement.
            self.configureHotkeys()

            // Skip panel rebuild during theme preview (the panel updates
            // colors directly via previewTheme).
            if self.panel.suppressConfigRebuild { return }

            let wasVisible = self.panel.isVisible
            self.panel.hide()
            self.panel = LauncherPanelController(config: self.config)
            if wasVisible {
                self.panel.show()
            }
            print("UI rebuilt with new config")
        }

        // Always hidden at startup, including manual and macOS login launches.
    }

    private func configureHotkeys() {
        guard let hotkeys else { return }
        do {
            let binding = try HotkeyBinding.parse(config.keybindings.open)
            _ = try HotkeyBinding.parse(config.keybindings.close)
            try hotkeys.replace(with: [.init(name: "launcher", binding: binding, action: { [weak self] in self?.panel.toggle() })])
        } catch {
            showHotkeyError(error)
            // On startup install the default if possible. On reload this is
            // attempted only when no launcher has ever been registered.
            if !hasWorkingHotkey {
                do {
                    try hotkeys.replace(with: [.init(name: "launcher", binding: try HotkeyBinding.parse("Alt+Space"),
                        action: { [weak self] in self?.panel.toggle() })])
                    hasWorkingHotkey = true
                } catch { showHotkeyError(error) }
            }
            return
        }
        hasWorkingHotkey = true
    }
    private var hasWorkingHotkey = false

    private func showHotkeyError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Walter hotkey registration failed"
        alert.informativeText = "\(error)\n\nEdit \(config.configURL.path). A previously working launcher binding is kept when possible. Walter does not change system shortcuts."
        alert.alertStyle = .warning
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func setupEditMenu() {
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let editMenuItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        editMenuItem.submenu = editMenu

        let mainMenu = NSMenu()
        mainMenu.addItem(editMenuItem)
        NSApp.mainMenu = mainMenu
    }
}
