// Application lifetime owns hotkeys and indexes independently of popup rebuilds.
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let configLocationPresenter = ConfigLocationPresenter()
    private var hotkeys: ApplicationHotkeys?
    private var panel: LauncherPanelController!
    private var config: ConfigManager!
    private var appIndex: AppIndex!
    private var symbolIndex: SymbolIndex!

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let url = WalterResources.bundle.url(forResource: "AppIcon", withExtension: "icns") {
            NSApp.applicationIconImage = NSImage(contentsOf: url)
        }
        config = ConfigManager()
        appIndex = AppIndex { [weak self] in self?.panel?.refreshResults() }
        // Publish built-ins for subsequent lookups; completion must not reset a
        // visible selection. Neither snapshot preparation belongs to a panel.
        symbolIndex = SymbolIndex()
        panel = LauncherPanelController(config: config, appIndex: appIndex, symbolIndex: symbolIndex,
            showConfigLocation: { [weak self] in self?.showConfigLocation() })
        do {
            hotkeys = ApplicationHotkeys(manager: HotkeyManager(backend: try CarbonHotkeyBackend()),
                toggle: { [weak self] in self?.panel.toggle() },
                report: { [weak self] in self?.showHotkeyError($0) })
            configureHotkeys()
        } catch { showHotkeyError(error) }
        setupEditMenu()
        config.onChange = { [weak self] in
            guard let self else { return }
            self.configureHotkeys()
            // Global registrations survive theme preview and panel replacement.
            guard !self.panel.suppressConfigRebuild else { return }
            let visible = self.panel.isVisible
            self.panel.hide()
            self.panel = LauncherPanelController(config: self.config, appIndex: self.appIndex,
                symbolIndex: self.symbolIndex,
                showConfigLocation: { [weak self] in self?.showConfigLocation() })
            if visible { self.panel.show() }
        }
        // Always hidden at startup, including manual and macOS login launches.
    }

    private func configureHotkeys() {
        hotkeys?.apply(config)
    }

    func applicationWillTerminate(_ notification: Notification) {
        config?.stopWatching()
        hotkeys = nil
    }

    private func showHotkeyError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Walter hotkey registration failed"
        alert.informativeText = "\(error)\n\nEdit \(config.configURL.path). A previously working launcher binding is kept when possible. Walter does not change system shortcuts."
        alert.alertStyle = .warning
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func showConfigLocation() {
        guard panel.isVisible else { return }
        configLocationPresenter.show(configURL: config.configURL, present: { notice in
            let alert = NSAlert()
            alert.messageText = notice.title
            alert.informativeText = notice.message
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: "Cancel") // Native Escape dismissal; neither button changes settings.
            alert.runModal()
        }, restoreFocus: { [weak self] in
            // A config reload may have replaced the panel while the alert ran.
            self?.panel.restoreInputFocus()
        })
    }

    private func setupEditMenu() {
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let item = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        item.submenu = edit
        let menu = NSMenu(); menu.addItem(item); NSApp.mainMenu = menu
    }
}
