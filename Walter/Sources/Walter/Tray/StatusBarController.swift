// Retained cleanup-baseline tray. Hotkey and app lifetime do not depend on it.
import AppKit

final class StatusBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let config: ConfigManager

    init(config: ConfigManager) {
        self.config = config
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        if let button = statusItem.button {
            if let url = WalterResources.bundle.url(forResource: "menubar_icon", withExtension: "png"),
               let icon = NSImage(contentsOf: url) {
                icon.size = NSSize(width: 18, height: 18)
                icon.isTemplate = true
                button.image = icon
            } else { button.title = "W" }
        }
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    deinit { NSStatusBar.system.removeStatusItem(statusItem) }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let themes = NSMenu()
        for name in config.allThemes.keys.sorted() {
            let item = NSMenuItem(title: name, action: #selector(selectTheme(_:)), keyEquivalent: "")
            item.representedObject = name
            item.target = self
            item.state = config.theme.name?.lowercased() == name ? .on : .off
            themes.addItem(item)
        }
        let themeItem = NSMenuItem(title: "Change Theme", action: nil, keyEquivalent: "")
        themeItem.submenu = themes
        menu.addItem(themeItem)
        menu.addItem(.separator())
        let about = NSMenuItem(title: "About Walter", action: #selector(aboutClicked), keyEquivalent: "")
        about.target = self
        menu.addItem(about)
        let quit = NSMenuItem(title: "Quit Walter", action: #selector(quitClicked), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    @objc private func selectTheme(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        config.selectTheme(name)
    }

    @objc private func aboutClicked() {
        let alert = NSAlert()
        alert.messageText = "Walter"
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "local"
        alert.informativeText = "Version \(version)\nPersonal local build."
        if let url = WalterResources.bundle.url(forResource: "AppIcon", withExtension: "icns") {
            alert.icon = NSImage(contentsOf: url)
        }
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @objc private func quitClicked() { NSApp.terminate(nil) }
}
