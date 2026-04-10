// StatusBarController.swift — Menu bar (status bar) icon and menu

import AppKit
import ServiceManagement

class StatusBarController {

    private let statusItem: NSStatusItem
    private let onToggle: () -> Void
    private var loginItem: NSMenuItem!

    init(onToggle: @escaping () -> Void, onQuit: @escaping () -> Void) {
        self.onToggle = onToggle

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            if let image = NSImage(systemSymbolName: "command", accessibilityDescription: "Walter") {
                image.isTemplate = true
                button.image = image
            } else {
                button.title = "W"
            }
        }

        // Build menu
        let menu = NSMenu()

        let toggleItem = NSMenuItem(title: "Toggle Walter", action: #selector(toggleClicked), keyEquivalent: "")
        toggleItem.target = self
        menu.addItem(toggleItem)

        menu.addItem(.separator())

        // Login item toggle — reflects current state
        loginItem = NSMenuItem(title: "Launch at Login", action: #selector(loginItemToggled), keyEquivalent: "")
        loginItem.target = self
        if #available(macOS 13.0, *) {
            loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        }
        menu.addItem(loginItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit Walter", action: #selector(quitClicked), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    @objc private func toggleClicked() {
        onToggle()
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
}
