// LauncherPanelController.swift — The floating launcher window
//
// All dimensions use config.s() so the entire UI scales from a single
// `scale` value in config.toml (e.g. scale = 1.5 makes everything 50% bigger).
//
// Visual design: NSVisualEffectView (.hudWindow) for frosted glass blur,
// SF Symbol search icon, 1px separator, system accent color selection.

import AppKit

class LauncherPanelController: NSObject {

    private let panel: KeyablePanel
    private let vibrancyView: NSVisualEffectView
    private let searchField: NSTextField
    private let searchIcon: NSImageView
    private let separator: NSBox
    private let resultsView: ResultsListView
    private var launcher: LauncherEngine!
    private let config: ConfigManager

    private var selectedIndex = 0
    private var previousApp: NSRunningApplication?

    init(config: ConfigManager) {
        self.config = config

        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let width = min(config.s(CGFloat(config.layout.width)), screenFrame.width * 0.95)
        let inputHeight = config.s(72)

        // --- Panel ---
        panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: inputHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        // --- Vibrancy ---
        vibrancyView = NSVisualEffectView()
        vibrancyView.material = .hudWindow
        vibrancyView.blendingMode = .behindWindow
        vibrancyView.state = .active
        vibrancyView.wantsLayer = true
        vibrancyView.layer?.cornerRadius = config.s(CGFloat(config.theme.borderRadius))
        vibrancyView.layer?.masksToBounds = true
        vibrancyView.translatesAutoresizingMaskIntoConstraints = false

        // --- Search icon ---
        searchIcon = NSImageView()
        if let img = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "Search") {
            let cfg = NSImage.SymbolConfiguration(pointSize: config.s(22), weight: .medium)
            searchIcon.image = img.withSymbolConfiguration(cfg)
            searchIcon.contentTintColor = .tertiaryLabelColor
        }
        searchIcon.translatesAutoresizingMaskIntoConstraints = false

        // --- Search field ---
        searchField = NSTextField()
        searchField.placeholderString = "Search apps..."
        searchField.font = .systemFont(ofSize: config.s(28), weight: .light)
        searchField.isBezeled = false
        searchField.focusRingType = .none
        searchField.drawsBackground = false
        searchField.textColor = .labelColor
        searchField.translatesAutoresizingMaskIntoConstraints = false

        // --- Separator ---
        separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        // --- Results ---
        resultsView = ResultsListView(config: config)
        resultsView.translatesAutoresizingMaskIntoConstraints = false

        super.init()

        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true

        // The content view must also clip to rounded corners — otherwise the
        // system draws a square window border around the vibrancy view's rounded layer.
        let contentView = panel.contentView!
        contentView.wantsLayer = true
        contentView.layer?.cornerRadius = config.s(CGFloat(config.theme.borderRadius))
        contentView.layer?.masksToBounds = true

        contentView.addSubview(vibrancyView)
        vibrancyView.addSubview(searchIcon)
        vibrancyView.addSubview(searchField)
        vibrancyView.addSubview(separator)
        vibrancyView.addSubview(resultsView)

        NSLayoutConstraint.activate([
            vibrancyView.topAnchor.constraint(equalTo: contentView.topAnchor),
            vibrancyView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            vibrancyView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            vibrancyView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),

            searchIcon.leadingAnchor.constraint(equalTo: vibrancyView.leadingAnchor, constant: config.s(20)),
            searchIcon.centerYAnchor.constraint(equalTo: searchField.centerYAnchor),
            searchIcon.widthAnchor.constraint(equalToConstant: config.s(26)),
            searchIcon.heightAnchor.constraint(equalToConstant: config.s(26)),

            searchField.topAnchor.constraint(equalTo: vibrancyView.topAnchor, constant: config.s(18)),
            searchField.leadingAnchor.constraint(equalTo: searchIcon.trailingAnchor, constant: config.s(12)),
            searchField.trailingAnchor.constraint(equalTo: vibrancyView.trailingAnchor, constant: -config.s(20)),
            searchField.heightAnchor.constraint(equalToConstant: config.s(36)),

            separator.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: config.s(14)),
            separator.leadingAnchor.constraint(equalTo: vibrancyView.leadingAnchor, constant: config.s(16)),
            separator.trailingAnchor.constraint(equalTo: vibrancyView.trailingAnchor, constant: -config.s(16)),

            resultsView.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: config.s(4)),
            resultsView.leadingAnchor.constraint(equalTo: vibrancyView.leadingAnchor),
            resultsView.trailingAnchor.constraint(equalTo: vibrancyView.trailingAnchor),
            resultsView.bottomAnchor.constraint(equalTo: vibrancyView.bottomAnchor),
        ])

        launcher = LauncherEngine(onIndexChanged: { [weak self] in
            guard let self, self.panel.isVisible else { return }
            self.updateResults(query: self.searchField.stringValue)
        })

        searchField.delegate = self

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidResignActive),
            name: NSApplication.didResignActiveNotification,
            object: nil
        )

        updateResults(query: "")
    }

    // MARK: - Show / Hide / Toggle

    func show() {
        let frontmost = NSWorkspace.shared.frontmostApplication
        if frontmost?.bundleIdentifier != Bundle.main.bundleIdentifier {
            previousApp = frontmost
        }
        restoreOrCenterPosition()
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(searchField)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hide() {
        savePosition()
        panel.orderOut(nil)
        resetState()
        if let app = previousApp {
            app.activate()
            previousApp = nil
        }
    }

    func toggle() {
        panel.isVisible ? hide() : show()
    }

    @objc private func appDidResignActive() {
        if panel.isVisible { hide() }
    }

    // MARK: - Internal

    // Save/restore the top-left corner (not the origin, which is bottom-left).
    // The panel's height changes as results appear/disappear, which shifts the
    // bottom-left origin. The top-left stays visually stable.
    private static let posXKey = "walter.panel.x"
    private static let posTopYKey = "walter.panel.topY"

    private func restoreOrCenterPosition() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: Self.posXKey) != nil {
            let x = CGFloat(defaults.double(forKey: Self.posXKey))
            let topY = CGFloat(defaults.double(forKey: Self.posTopYKey))
            let y = topY - panel.frame.height
            let origin = NSPoint(x: x, y: y)

            // Safety: only restore if the panel would be visible on some screen.
            // Protects against stale positions from resolution changes, disconnected
            // monitors, or scale factor changes that push the panel off-screen.
            if isOnScreen(origin: origin) {
                panel.setFrameOrigin(origin)
                return
            }
        }
        centerOnScreen()
    }

    /// Returns true if at least part of the panel would be visible on any connected screen.
    private func isOnScreen(origin: NSPoint) -> Bool {
        let panelRect = NSRect(origin: origin, size: panel.frame.size)
        for screen in NSScreen.screens {
            if panelRect.intersects(screen.visibleFrame) {
                return true
            }
        }
        return false
    }

    private func centerOnScreen() {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let x = screenFrame.midX - panel.frame.width / 2
        let y = screenFrame.midY + screenFrame.height * 0.2
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func savePosition() {
        let frame = panel.frame
        UserDefaults.standard.set(Double(frame.origin.x), forKey: Self.posXKey)
        // Store top-left Y (origin.y + height) so it's stable across height changes
        UserDefaults.standard.set(Double(frame.origin.y + frame.height), forKey: Self.posTopYKey)
    }

    private func resetState() {
        searchField.stringValue = ""
        selectedIndex = 0
        updateResults(query: "")
    }

    private func updateResults(query: String) {
        let results = launcher.search(query: query)
        selectedIndex = 0
        resultsView.update(results: results, selectedIndex: selectedIndex)
        resizePanelToFit(resultCount: results.count)
        separator.isHidden = results.isEmpty
    }

    private func resizePanelToFit(resultCount: Int) {
        let inputHeight = config.s(72)
        let separatorHeight: CGFloat = resultCount > 0 ? config.s(18) : 0
        let rowHeight = config.s(64)
        let maxRows = min(resultCount, config.layout.maxResults)
        let resultsHeight = CGFloat(maxRows) * rowHeight + (maxRows > 0 ? config.s(8) : 0)

        // Clamp to 90% of screen height so large scale factors don't overflow
        let screenHeight = NSScreen.main?.visibleFrame.height ?? 900
        let maxHeight = screenHeight * 0.9
        let newHeight = min(inputHeight + separatorHeight + resultsHeight, maxHeight)

        var frame = panel.frame
        let delta = newHeight - frame.height
        frame.origin.y -= delta
        frame.size.height = newHeight
        panel.setFrame(frame, display: true, animate: false)
    }

    private func moveSelection(by delta: Int) {
        let count = resultsView.resultCount
        guard count > 0 else { return }
        selectedIndex = (selectedIndex + delta + count) % count
        resultsView.update(selectedIndex: selectedIndex)
    }

    private func confirmSelection() {
        if let result = resultsView.result(at: selectedIndex) {
            launcher.launch(result: result)
        }
        hide()
    }
}

// MARK: - NSTextFieldDelegate

extension LauncherPanelController: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        updateResults(query: searchField.stringValue)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            hide(); return true
        }
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            confirmSelection(); return true
        }
        if commandSelector == #selector(NSResponder.insertTab(_:)) {
            moveSelection(by: 1); return true
        }
        if commandSelector == #selector(NSResponder.insertBacktab(_:)) {
            moveSelection(by: -1); return true
        }
        if commandSelector == #selector(NSResponder.moveDown(_:)) {
            moveSelection(by: 1); return true
        }
        if commandSelector == #selector(NSResponder.moveUp(_:)) {
            moveSelection(by: -1); return true
        }
        return false
    }
}
