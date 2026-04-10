// AppDelegate.swift — Wires together all subsystems on launch
//
// Owns the top-level objects that must live for the process lifetime:
//   - StatusBarController (tray icon + menu)
//   - HotkeyManager (global Alt+Space listener)
//   - LauncherPanelController (the floating search window)
//   - ConfigManager (TOML config loading + hot-reload)
//
// The panel is shown on first launch; after that, Alt+Space toggles it.

import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusBar: StatusBarController!
    private var hotkey: HotkeyManager!
    private var panel: LauncherPanelController!
    private var config: ConfigManager!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Load config (falls back to defaults if file is missing)
        config = ConfigManager()

        // Create the launcher panel (hidden initially)
        panel = LauncherPanelController(config: config)

        // Menu bar icon with Quit action
        statusBar = StatusBarController(onToggle: { [weak self] in
            self?.panel.toggle()
        }, onQuit: {
            NSApp.terminate(nil)
        })

        // Global hotkey: Alt+Space
        hotkey = HotkeyManager(keyCode: 49, modifiers: .option) { [weak self] in
            self?.panel.toggle()
        }

        // Agent apps have no menu bar, so Cmd+A/C/V/X don't work without
        // an explicit Edit menu. We create a hidden one so the system binds
        // standard text editing shortcuts to the text field's field editor.
        setupEditMenu()

        // Show the panel on first launch
        panel.show()
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
