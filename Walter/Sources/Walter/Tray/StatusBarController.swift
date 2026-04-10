// StatusBarController.swift — Menu bar icon, theme picker, and settings

import AppKit
import ServiceManagement

class StatusBarController {

    private let statusItem: NSStatusItem
    private let onToggle: () -> Void
    private var loginItem: NSMenuItem!
    private weak var config: ConfigManager?

    init(config: ConfigManager, onToggle: @escaping () -> Void, onQuit: @escaping () -> Void) {
        self.onToggle = onToggle
        self.config = config

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            // Load the dedicated menu bar icon (black on transparent).
            // isTemplate = true tells macOS to invert it in dark mode.
            if let iconURL = Bundle.module.url(forResource: "menubar_icon", withExtension: "png"),
               let icon = NSImage(contentsOf: iconURL) {
                icon.size = NSSize(width: 18, height: 18)
                icon.isTemplate = true
                button.image = icon
            } else {
                button.title = "W"
            }
        }

        let menu = NSMenu()

        let toggleItem = NSMenuItem(title: "Toggle Walter", action: #selector(toggleClicked), keyEquivalent: "")
        toggleItem.target = self
        menu.addItem(toggleItem)

        menu.addItem(.separator())

        // Theme submenu
        let themeItem = NSMenuItem(title: "Change Theme", action: nil, keyEquivalent: "")
        themeItem.submenu = buildThemeMenu()
        menu.addItem(themeItem)

        menu.addItem(.separator())

        // Login item toggle
        loginItem = NSMenuItem(title: "Launch at Login", action: #selector(loginItemToggled), keyEquivalent: "")
        loginItem.target = self
        if #available(macOS 13.0, *) {
            loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        }
        menu.addItem(loginItem)

        // Open config file
        let configItem = NSMenuItem(title: "Edit Config...", action: #selector(openConfig), keyEquivalent: ",")
        configItem.target = self
        menu.addItem(configItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit Walter", action: #selector(quitClicked), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    // MARK: - Theme menu

    private func buildThemeMenu() -> NSMenu {
        let menu = NSMenu()
        let currentTheme = config?.theme.name?.lowercased()

        // Group themes: dark first, then light
        let darkThemes = ["catppuccin-mocha", "catppuccin-macchiato", "catppuccin-frappe",
                          "nord", "dracula", "gruvbox", "solarized-dark", "rose-pine",
                          "rose-pine-moon", "tokyo-night", "one-dark", "kanagawa",
                          "everforest", "ayu-dark"]
        let lightThemes = ["catppuccin-latte", "solarized-light", "github-light",
                           "rose-pine-dawn", "ayu-light", "everforest-light"]

        // System default
        addThemeItem(to: menu, name: "spotlight", currentTheme: currentTheme, displayOverride: "Spotlight (Default)")
        menu.addItem(.separator())

        // Dark section
        let darkHeader = NSMenuItem(title: "Dark", action: nil, keyEquivalent: "")
        darkHeader.isEnabled = false
        menu.addItem(darkHeader)

        for name in darkThemes {
            addThemeItem(to: menu, name: name, currentTheme: currentTheme)
        }

        menu.addItem(.separator())

        // Light section
        let lightHeader = NSMenuItem(title: "Light", action: nil, keyEquivalent: "")
        lightHeader.isEnabled = false
        menu.addItem(lightHeader)

        for name in lightThemes {
            addThemeItem(to: menu, name: name, currentTheme: currentTheme)
        }

        menu.addItem(.separator())

        // Custom option
        let customItem = NSMenuItem(title: "Custom (edit config)", action: #selector(openConfig), keyEquivalent: "")
        customItem.target = self
        if currentTheme == nil {
            customItem.state = .on
        }
        menu.addItem(customItem)

        return menu
    }

    private func addThemeItem(to menu: NSMenu, name: String, currentTheme: String?, displayOverride: String? = nil) {
        guard let preset = builtinThemes[name] else { return }

        let displayName = displayOverride ?? name.split(separator: "-").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
        let item = NSMenuItem(title: displayName, action: #selector(themeSelected(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = name

        // Color swatch as the menu item image
        item.image = colorSwatch(hex: preset.accent)

        // Checkmark on the active theme
        if name == currentTheme {
            item.state = .on
        }

        menu.addItem(item)
    }

    /// Creates a tiny colored circle for the menu item.
    private func colorSwatch(hex: String) -> NSImage {
        let size = NSSize(width: 12, height: 12)
        let image = NSImage(size: size)
        image.lockFocus()
        let color = NSColor(hex: hex) ?? .controlAccentColor
        color.setFill()
        NSBezierPath(ovalIn: NSRect(origin: .zero, size: size)).fill()
        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    // MARK: - Actions

    @objc private func toggleClicked() {
        onToggle()
    }

    @objc private func themeSelected(_ sender: NSMenuItem) {
        guard let themeName = sender.representedObject as? String,
              let config = config else { return }

        // Write the theme name into config.toml — hot-reload picks it up.
        updateConfigFile(key: "name", value: "\"\(themeName)\"", section: "theme")
    }

    @objc private func openConfig() {
        guard let config = config else { return }
        NSWorkspace.shared.open(config.configURL)
    }

    @objc private func loginItemToggled() {
        if loginItem.state == .on {
            LoginItemManager.disableLoginItem()
            loginItem.state = .off
        } else {
            LoginItemManager.enableLoginItem()
            loginItem.state = .on
        }
    }

    @objc private func quitClicked() {
        NSApp.terminate(nil)
    }

    // MARK: - Config file editing

    /// Inserts or updates a key in a [section] of the TOML config file.
    private func updateConfigFile(key: String, value: String, section: String) {
        guard let config = config else { return }
        let url = config.configURL

        guard var content = try? String(contentsOf: url, encoding: .utf8) else { return }

        let lines = content.components(separatedBy: "\n")
        var result: [String] = []
        var inSection = false
        var keyWritten = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Detect section headers
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                // If we were in the target section and didn't find the key, insert it
                if inSection && !keyWritten {
                    result.append("\(key) = \(value)")
                    keyWritten = true
                }
                let sectionName = String(trimmed.dropFirst().dropLast())
                inSection = (sectionName == section)
            }

            // If we're in the target section, look for the key
            if inSection && trimmed.hasPrefix(key) && trimmed.contains("=") {
                // Check it's actually this key (not a prefix of another key)
                let parts = trimmed.split(separator: "=", maxSplits: 1)
                let existingKey = parts[0].trimmingCharacters(in: .whitespaces)
                if existingKey == key || existingKey == "# \(key)" {
                    result.append("\(key) = \(value)")
                    keyWritten = true
                    continue
                }
            }

            result.append(line)
        }

        // If we never found the section or key, append at the end
        if !keyWritten {
            if !inSection {
                result.append("")
                result.append("[\(section)]")
            }
            result.append("\(key) = \(value)")
        }

        content = result.joined(separator: "\n")
        try? content.write(to: url, atomically: true, encoding: .utf8)
        // Hot-reload will pick up the change automatically
    }
}
