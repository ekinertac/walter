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
        // Set the app icon (used in About dialog, Cmd+Tab if ever shown, etc.)
        if let iconURL = Bundle.module.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = icon
        }

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

        // Check Accessibility permission — required for the global hotkey.
        // When running as a .app bundle, Walter itself needs the permission
        // (unlike swift run, which piggybacks on Terminal's permission).
        requestAccessibilityIfNeeded()

        // Global hotkey from config (e.g. "Alt+Space", "Alt+Tab", "Ctrl+Space")
        let (keyCode, modifiers) = HotkeyManager.parseBinding(config.keybindings.open)
        hotkey = HotkeyManager(keyCode: keyCode, modifiers: modifiers) { [weak self] in
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

            // Re-create hotkey in case the binding changed
            let (kc, mods) = HotkeyManager.parseBinding(self.config.keybindings.open)
            self.hotkey = HotkeyManager(keyCode: kc, modifiers: mods) { [weak self] in
                self?.panel.toggle()
            }

            print("UI rebuilt with new config")
        }

        // Show the panel on first launch
        panel.show()
    }

    /// Prompts for Accessibility permission if not already granted.
    /// Uses AXIsProcessTrustedWithOptions which shows the native macOS dialog
    /// ("Walter would like to control this computer") on first run.
    private func requestAccessibilityIfNeeded() {
        let trusted = AXIsProcessTrusted()
        if !trusted {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
            print("Accessibility: not granted — prompting user")
        } else {
            print("Accessibility: granted")
        }
    }

    @objc private func openConfig() {
        let configPath = config.configURL.path
        let editorPath = config.general.editor.isEmpty
            ? "/System/Applications/TextEdit.app"
            : config.general.editor

        NSWorkspace.shared.open(
            [URL(fileURLWithPath: configPath)],
            withApplicationAt: URL(fileURLWithPath: editorPath),
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
