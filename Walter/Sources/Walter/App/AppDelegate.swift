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
        statusBar = StatusBarController(config: config, onToggle: { [weak self] in
            self?.panel.toggle()
        }, onQuit: {
            NSApp.terminate(nil)
        })

        // Global hotkey: Alt+Space
        hotkey = HotkeyManager(keyCode: 49, modifiers: .option) { [weak self] in
            self?.panel.toggle()
        }

        setupEditMenu()

        // Hot-reload: when config.toml is saved, rebuild the panel with new values.
        // Full teardown+rebuild is simpler and more reliable than patching every
        // property individually — the panel is cheap to construct.
        config.onChange = { [weak self] in
            guard let self else { return }
            // Skip rebuild when the panel itself is writing to config (theme preview)
            if self.panel.suppressConfigRebuild { return }
            let wasVisible = self.panel.isVisible
            self.panel.hide()
            self.panel = LauncherPanelController(config: self.config)
            if wasVisible {
                self.panel.show()
            }
            print("UI rebuilt with new config")
        }

        // Show the panel on first launch
        panel.show()
    }

    @objc private func openConfig() {
        let configPath = config.configURL.path
        let editorPath = config.general.editor

        let knownEditors = [
            "/Applications/Visual Studio Code.app",
            "/Applications/Cursor.app",
            "/Applications/Zed.app",
            "/Applications/Sublime Text.app",
            "/Applications/CotEditor.app",
            "/Applications/BBEdit.app",
            "/Applications/TextEdit.app",
        ]

        let editor: String
        if !editorPath.isEmpty {
            editor = editorPath
        } else if let found = knownEditors.first(where: { FileManager.default.fileExists(atPath: $0) }) {
            editor = found
        } else {
            NSWorkspace.shared.open(URL(fileURLWithPath: configPath))
            return
        }

        NSWorkspace.shared.open(
            [URL(fileURLWithPath: configPath)],
            withApplicationAt: URL(fileURLWithPath: editor),
            configuration: NSWorkspace.OpenConfiguration()
        )
    }

    private func setupEditMenu() {
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(.separator())

        let prefsItem = NSMenuItem(title: "Open Config", action: #selector(openConfig), keyEquivalent: ",")
        prefsItem.target = self
        editMenu.addItem(prefsItem)

        let editMenuItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        editMenuItem.submenu = editMenu

        let mainMenu = NSMenu()
        mainMenu.addItem(editMenuItem)
        NSApp.mainMenu = mainMenu
    }
}
