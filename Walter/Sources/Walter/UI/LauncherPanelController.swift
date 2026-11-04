// LauncherPanelController.swift — The floating launcher window
//
// Fixed scale, dynamic height; centered horizontally, top edge 30% down the pointer's screen.
// Theme colors are applied to a background layer + vibrancy overlay.
// Live theme preview paints colors directly without panel rebuild.

import AppKit

class LauncherPanelController: NSObject {

    private let panel: KeyablePanel
    private let backgroundLayer: CALayer       // solid color behind vibrancy
    private let vibrancyView: NSVisualEffectView
    private let searchField: NSTextField
    private let searchIcon: NSImageView
    private let separator: NSBox
    private let resultsView: any ResultsView
    private var launcher: LauncherEngine!
    private let config: ConfigManager
    private let appIndex: AppIndex

    private var selectedIndex = 0
    private var previousApp: NSRunningApplication?
    private var isThemePicker = false
    var suppressConfigRebuild = false

    init(config: ConfigManager, appIndex: AppIndex, symbolIndex: SymbolIndex,
         showConfigLocation: @escaping () -> Void) {
        self.config = config
        self.appIndex = appIndex

        let screenFrame = Self.pointerScreenFrame
        let width = min(config.s(CGFloat(config.layout.width)), screenFrame.width * 0.95)
        let inputHeight = config.s(72)
        let cornerRadius = config.s(CGFloat(config.theme.borderRadius))

        // --- Panel ---
        panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: inputHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        // --- Background color layer (behind vibrancy) ---
        backgroundLayer = CALayer()
        backgroundLayer.cornerRadius = cornerRadius
        backgroundLayer.masksToBounds = true
        let background = NSColor(hex: config.theme.background) ?? NSColor(white: 0.1, alpha: 1)
        backgroundLayer.backgroundColor = background.withAlphaComponent(background.alphaComponent * 0.92).cgColor

        // --- Vibrancy overlay (adds blur on top of the color) ---
        vibrancyView = NSVisualEffectView()
        vibrancyView.material = Self.blurMaterial(from: config.theme.blurMaterial)
        vibrancyView.blendingMode = .withinWindow
        vibrancyView.state = .active
        vibrancyView.wantsLayer = true
        vibrancyView.layer?.cornerRadius = cornerRadius
        vibrancyView.layer?.masksToBounds = true
        // Optional theme border. Hairline by default; off when unset.
        if let border = config.theme.border, let c = NSColor(hex: border) {
            vibrancyView.layer?.borderColor = c.cgColor
            vibrancyView.layer?.borderWidth = 1
        }
        vibrancyView.translatesAutoresizingMaskIntoConstraints = false

        // --- Search icon ---
        let iconColor = NSColor(hex: config.theme.foreground)?.withAlphaComponent(0.5) ?? .tertiaryLabelColor
        searchIcon = NSImageView()
        if let img = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "Search") {
            let cfg = NSImage.SymbolConfiguration(pointSize: config.s(22), weight: .medium)
            searchIcon.image = img.withSymbolConfiguration(cfg)
            searchIcon.contentTintColor = iconColor
        }
        searchIcon.translatesAutoresizingMaskIntoConstraints = false

        // --- Search field ---
        let fgColor = NSColor(hex: config.theme.foreground) ?? .labelColor
        let placeholderColor = config.theme.placeholderColor.flatMap { NSColor(hex: $0) }
            ?? fgColor.withAlphaComponent(0.5)
        let searchFont = Self.resolveFont(name: config.theme.font, size: config.s(28), weight: .light)
        // Keep glyphs and cursor centered even when a long query shrinks.
        searchField = CenteredTextField()
        searchField.font = searchFont
        // Attributed placeholder must carry the field's font explicitly —
        // without it the placeholder reverts to the default system size
        // (tiny) instead of matching the large search input.
        searchField.placeholderAttributedString = NSAttributedString(
            string: config.layout.placeholder,
            attributes: [.foregroundColor: placeholderColor, .font: searchFont]
        )
        searchField.isBezeled = false
        searchField.focusRingType = .none
        searchField.drawsBackground = false
        // Lock the cell to single-line, horizontally-scrolling behavior.
        // Long queries must not wrap outside the input area.
        searchField.cell?.usesSingleLineMode = true
        searchField.cell?.wraps = false
        searchField.cell?.isScrollable = true
        searchField.lineBreakMode = .byTruncatingHead
        searchField.textColor = fgColor
        searchField.translatesAutoresizingMaskIntoConstraints = false

        // --- Separator ---
        separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        // --- Results ---
        // Pick the renderer based on layout.mode. List is the default; the
        // grid mode mirrors the macOS Tahoe Spotlight aesthetic with large
        // icon tiles.
        if config.layout.mode.lowercased() == "grid" {
            resultsView = ResultsGridView(config: config)
        } else {
            resultsView = ResultsListView(config: config)
        }
        resultsView.translatesAutoresizingMaskIntoConstraints = false

        super.init()

        // Panel setup
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true

        // Content view with rounded corners
        let contentView = panel.contentView!
        contentView.wantsLayer = true
        contentView.layer?.cornerRadius = cornerRadius
        contentView.layer?.masksToBounds = true

        // Layer hierarchy: background color → vibrancy overlay → UI elements
        contentView.layer?.addSublayer(backgroundLayer)
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

        launcher = LauncherEngine(config: config,
            entries: { [weak appIndex] in appIndex?.allEntries ?? [] },
            symbolLoader: { [weak symbolIndex] name, description in
                symbolIndex?.image(name: name, description: description)
            })

        resultsView.onRowClicked = { [weak self] index in
            guard let self else { return }
            self.selectedIndex = index
            self.resultsView.update(selectedIndex: index)
            self.confirmSelection()
        }

        searchField.delegate = self
        panel.closeBinding = (try? HotkeyBinding.parse(config.keybindings.close)) ?? (try? HotkeyBinding.parse("Escape"))
        panel.onClose = { [weak self] in self?.cancelSelection() }
        panel.onQuit = { NSApp.terminate(nil) }
        panel.onConfigLocation = showConfigLocation

        // Cmd-shortcuts arrive as key-equivalents, not editing commands, so
        // they're handled at the panel level rather than in doCommandBy:.
        panel.onCommandReturn = { [weak self] in self?.revealAllowedApp() }
        panel.onQuickSelect = { [weak self] n in self?.quickSelect(n) }
        panel.onCopyResult = { [weak self] in self?.copySelectionValue() ?? false }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidResignActive),
            name: NSApplication.didResignActiveNotification,
            object: nil
        )

        updateResults(query: "")
    }

    // Keep background layer sized to the content view
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        backgroundLayer.frame = panel.contentView?.bounds ?? .zero
    }

    // MARK: - Show / Hide / Toggle

    var isVisible: Bool { panel.isVisible }

    func show() {
        let frontmost = NSWorkspace.shared.frontmostApplication
        if frontmost?.bundleIdentifier != Bundle.main.bundleIdentifier {
            previousApp = frontmost
        }
        positionOnScreen()
        // Sync background layer size
        backgroundLayer.frame = panel.contentView?.bounds ?? .zero
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(searchField)
        NSApp.activate(ignoringOtherApps: true)
        // Present the existing snapshot first. A throttled background hedge
        // prepares future queries without rebuilding this visible selection.
        appIndex.refreshForPopup()
    }

    func hide() {
        panel.orderOut(nil)
        if isThemePicker { restoreConfiguredTheme() }
        suppressConfigRebuild = false
        resetState()
        if let app = previousApp {
            app.activate()
            previousApp = nil
        }
    }

    func toggle() {
        panel.isVisible ? hide() : show()
    }

    /// Alert dismissal must not reveal a hidden/replaced popup or steal focus
    /// from another app. Do not call show(), reset the query, or refresh results.
    func restoreInputFocus() {
        guard ConfigLocationPresenter.shouldRestoreFocus(popupVisible: panel.isVisible,
            applicationActive: NSApp.isActive) else { return }
        panel.makeKeyAndOrderFront(nil)
        if let editor = searchField.currentEditor(), panel.firstResponder === editor { return }
        panel.makeFirstResponder(searchField)
    }

    @objc private func appDidResignActive() {
        if panel.isVisible { hide() }
    }

    private static var pointerScreenFrame: NSRect {
        PopupGeometry.visibleFrame(pointer: NSEvent.mouseLocation,
            screens: NSScreen.screens.map { ($0.frame, $0.visibleFrame) }, fallback: NSScreen.main?.visibleFrame)
    }

    private func positionOnScreen(height: CGFloat? = nil) {
        let frame = PopupGeometry.fittedFrame(width: CGFloat(config.layout.width),
            height: height ?? panel.frame.height, in: Self.pointerScreenFrame)
        guard panel.frame != frame else { return }
        // Size and position change together. Do not force drawing inside the
        // text-change delegate; AppKit can render input/results together at the
        // normal display pass, after the entire update has completed.
        panel.setFrame(frame, display: false, animate: false)
        panel.contentView?.needsDisplay = true
    }

    func refreshResults() {
        guard panel.isVisible else { return }
        updateResults(query: searchField.stringValue)
    }

    // MARK: - State

    private func resetState() {
        searchField.stringValue = ""
        // Restore the input font to the base size so the next open
        // doesn't briefly flash whatever shrunk size the last query left.
        adjustInputFontSize()
        selectedIndex = 0
        isThemePicker = false
        setPlaceholder(config.layout.placeholder)
        updateResults(query: "")
    }

    private func updateResults(query: String) {
        let timing = InputTiming.shared
        let results = timing.measure(.search) {
            isThemePicker ? launcher.themeResults(filter: query) : launcher.search(query: query)
        }
        selectedIndex = 0
        timing.measure(.views) { resultsView.update(results: results, selectedIndex: selectedIndex) }
        // Apply the current palette to both reused and newly allocated views;
        // retained slots must not preserve an old preview palette.
        timing.measure(.colors) {
            applyResultColors()
            separator.isHidden = results.isEmpty
        }
        timing.measure(.geometry) { resizePanelToFit(resultCount: results.count, results: results) }
        if isThemePicker { notifyPreviewIfNeeded() }
    }

    /// Resolves the configured theme palette (with fallbacks for the
    /// optional selection/subtitle colors) and pushes it to the results
    /// view. Centralizes the fallback logic so list and grid renderers and
    /// the live theme preview all agree on what "selection" / "subtitle"
    /// mean when the theme doesn't specify them.
    private func applyResultColors() {
        let c = Self.resolvePalette(
            foreground: config.theme.foreground,
            accent: config.theme.accent,
            selection: config.theme.selection,
            subtitle: config.theme.subtitle
        )
        resultsView.updateColors(foreground: c.fg, accent: c.accent, selection: c.selection, subtitle: c.subtitle)
    }

    /// Resolves a palette from hex strings, deriving the optional colors
    /// from the core ones when unset: selection = accent @ 0.25,
    /// subtitle = foreground @ 0.6.
    static func resolvePalette(foreground: String, accent: String, selection: String?, subtitle: String?)
        -> (fg: NSColor, accent: NSColor, selection: NSColor, subtitle: NSColor) {
        let fg = NSColor(hex: foreground) ?? .labelColor
        let ac = NSColor(hex: accent) ?? .controlAccentColor
        let sel = selection.flatMap { NSColor(hex: $0) } ?? ac.withAlphaComponent(0.25)
        let sub = subtitle.flatMap { NSColor(hex: $0) } ?? fg.withAlphaComponent(0.6)
        return (fg, ac, sel, sub)
    }

    private func resizePanelToFit(resultCount: Int, results: [SearchResult]) {
        let inputHeight = config.s(72)
        let separatorHeight: CGFloat = resultCount > 0 ? config.s(18) : 0
        let resultsHeight = resultsView.contentHeight(for: results, maxRows: config.layout.maxResults)
        positionOnScreen(height: inputHeight + separatorHeight + resultsHeight)

        // Keep background layer in sync with the new frame
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        backgroundLayer.frame = panel.contentView?.bounds ?? .zero
        CATransaction.commit()
    }

    private func moveSelection(by delta: Int) {
        let count = resultsView.resultCount
        guard count > 0 else { return }
        selectedIndex = resultsView.step(by: delta, from: selectedIndex)
        resultsView.update(selectedIndex: selectedIndex)
        notifyPreviewIfNeeded()
    }

    /// Two-dimensional move (used by grid mode for left/right keys).
    /// In list mode the grid view's `step(dx:dy:)` ignores horizontal motion.
    private func moveSelection(dx: Int, dy: Int) {
        let count = resultsView.resultCount
        guard count > 0 else { return }
        selectedIndex = resultsView.step(dx: dx, dy: dy, from: selectedIndex)
        resultsView.update(selectedIndex: selectedIndex)
        notifyPreviewIfNeeded()
    }

    /// Sets the search-field placeholder honoring the theme's placeholder
    /// color (falls back to foreground @ 0.5). Used everywhere the
    /// placeholder text changes so the color never silently reverts.
    private func setPlaceholder(_ text: String) {
        let color = config.theme.placeholderColor.flatMap { NSColor(hex: $0) }
            ?? (NSColor(hex: config.theme.foreground) ?? .labelColor).withAlphaComponent(0.5)
        // Reuse the field's own font so the placeholder matches the large
        // input size; an attributed string without an explicit font would
        // shrink to the default system size.
        var attrs: [NSAttributedString.Key: Any] = [.foregroundColor: color]
        if let font = searchField.font { attrs[.font] = font }
        searchField.placeholderAttributedString = NSAttributedString(string: text, attributes: attrs)
    }

    private func notifyPreviewIfNeeded() {
        if isThemePicker, let result = resultsView.result(at: selectedIndex),
           case .applyTheme(let name) = result.action {
            previewTheme(name)
        }
    }

    // MARK: - Theme preview

    /// Preview is local UI only; Enter explicitly persists the chosen theme.
    private func previewTheme(_ name: String) {
        guard let preset = config.allThemes[name] else { return }
        suppressConfigRebuild = true
        paintTheme(preset)
    }

    private func restoreConfiguredTheme() {
        paintTheme(ThemePreset(background: config.theme.background,
            foreground: config.theme.foreground, accent: config.theme.accent,
            selection: config.theme.selection, subtitle: config.theme.subtitle, border: config.theme.border))
    }

    private func paintTheme(_ preset: ThemePreset) {
        let bg = NSColor(hex: preset.background) ?? NSColor(white: 0.1, alpha: 1)
        let palette = Self.resolvePalette(
            foreground: preset.foreground,
            accent: preset.accent,
            selection: preset.selection,
            subtitle: preset.subtitle
        )

        // Background — transparent bg means "system vibrancy only" (Spotlight look)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if bg.alphaComponent == 0 {
            backgroundLayer.backgroundColor = CGColor.clear
        } else {
            backgroundLayer.backgroundColor = bg.withAlphaComponent(bg.alphaComponent * 0.92).cgColor
        }
        CATransaction.commit()

        searchField.textColor = palette.fg
        searchIcon.contentTintColor = palette.fg.withAlphaComponent(0.5)

        // Border follows the previewed theme (off when it doesn't set one).
        if let border = preset.border, let c = NSColor(hex: border) {
            vibrancyView.layer?.borderColor = c.cgColor
            vibrancyView.layer?.borderWidth = 1
        } else {
            vibrancyView.layer?.borderWidth = 0
        }

        resultsView.updateColors(foreground: palette.fg, accent: palette.accent,
                                 selection: palette.selection, subtitle: palette.subtitle)
    }

    /// Resolves a font by name from config. Falls back to system font if not found.
    static func resolveFont(name: String, size: CGFloat, weight: NSFont.Weight) -> NSFont {
        // "SF Pro", "system", or empty → system font
        let lower = name.lowercased()
        if lower.isEmpty || lower == "sf pro" || lower == "system" {
            return .systemFont(ofSize: size, weight: weight)
        }
        // Try the exact name as a font family
        if let font = NSFont(name: name, size: size) {
            return font
        }
        // Try with weight descriptor (e.g. "JetBrains Mono" → "JetBrainsMono-Regular")
        let descriptor = NSFontDescriptor(fontAttributes: [
            .family: name,
            .traits: [NSFontDescriptor.TraitKey.weight: weight]
        ])
        if let font = NSFont(descriptor: descriptor, size: size) {
            return font
        }
        return .systemFont(ofSize: size, weight: weight)
    }

    /// Maps a `font_weight` config string to an NSFont.Weight. Unknown
    /// values fall back to .medium (the historical result-title weight).
    static func fontWeight(from name: String) -> NSFont.Weight {
        switch name.lowercased() {
        case "ultralight":      return .ultraLight
        case "thin":            return .thin
        case "light":           return .light
        case "regular", "normal": return .regular
        case "medium":          return .medium
        case "semibold":        return .semibold
        case "bold":            return .bold
        case "heavy":           return .heavy
        case "black":           return .black
        default:                return .medium
        }
    }

    private static func blurMaterial(from name: String) -> NSVisualEffectView.Material {
        switch name.lowercased() {
        case "sidebar":    return .sidebar
        case "popover":    return .popover
        case "sheet":      return .sheet
        default:           return .hudWindow
        }
    }

    private func cancelSelection() {
        if isThemePicker {
            restoreConfiguredTheme()
            suppressConfigRebuild = false
            isThemePicker = false
            searchField.stringValue = ""
            setPlaceholder(config.layout.placeholder)
            updateResults(query: "")
        } else { hide() }
    }

    private func confirmSelection() {
        guard let result = resultsView.result(at: selectedIndex) else { return }

        switch result.action {
        case .enterThemePicker:
            isThemePicker = true
            searchField.stringValue = ""
            setPlaceholder("Filter themes...")
            updateResults(query: "")
            return

        case .applyTheme(let name):
            launcher.applyTheme(name: name)
            suppressConfigRebuild = false
            isThemePicker = false
            setPlaceholder(config.layout.placeholder)
            hide()
            return

        default:
            // Hide first so the panel disappears instantly on selection,
            // then launch async so NSWorkspace.open() doesn't stall the UI.
            hide()
            DispatchQueue.main.async { self.launcher.launch(result: result) }
        }
    }

    /// Shrinks the search input's font when the text is wider than the
    /// field can display at the base size, with a hard floor so it never
    /// becomes unreadable. Longer queries then scroll horizontally.
    private func adjustInputFontSize() {
        let text = searchField.stringValue
        let baseSize = config.s(28)
        let minSize = config.s(14)
        let baseFont = Self.resolveFont(name: config.theme.font, size: baseSize, weight: .light)

        // Empty input shows the placeholder, which we want at full size.
        guard !text.isEmpty else {
            if searchField.font != baseFont { searchField.font = baseFont }
            return
        }

        let fieldWidth = searchField.bounds.width
        guard fieldWidth > 0 else { return }

        let measured = (text as NSString).size(withAttributes: [.font: baseFont]).width
        let targetSize: CGFloat
        if measured <= fieldWidth {
            targetSize = baseSize
        } else {
            // Scale proportionally to fit, floored at the minimum so very
            // long pasted blobs don't render at one-pixel-tall.
            let scale = fieldWidth / measured
            targetSize = max(minSize, baseSize * scale)
        }

        searchField.font = Self.resolveFont(name: config.theme.font, size: targetSize, weight: .light)
    }

    /// Cmd+1…9 — jump to and launch the Nth visible result. No-op when
    /// fewer than N results are showing.
    private func quickSelect(_ n: Int) {
        let idx = n - 1
        guard idx >= 0, idx < resultsView.resultCount else { return }
        selectedIndex = idx
        resultsView.update(selectedIndex: idx)
        confirmSelection()
    }

    /// Cmd+C — copy the selected result's underlying value to the
    /// clipboard: revalidated app path, alias/Settings URL, or computed
    /// answer. Returns true if something was copied. The launcher hides
    /// afterward, matching the feel of completing an action.
    private func copySelectionValue() -> Bool {
        guard let result = resultsView.result(at: selectedIndex) else { return false }
        let text: String?
        switch result.action {
        case .openApp(let path): text = AllowedApps().validatedURL(for: path)?.path
        case .url(let u), .settings(let u): text = u
        case .copy(let v): text = v
        case .enterThemePicker, .applyTheme: text = nil
        }
        guard let text, !text.isEmpty else { return false }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        hide()
        return true
    }

    private func revealAllowedApp() {
        guard let result = resultsView.result(at: selectedIndex) else { return }
        guard case .openApp(let path) = result.action else { confirmSelection(); return }
        guard let url = AllowedApps().validatedURL(for: path) else { return }
        hide()
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

// MARK: - NSTextFieldDelegate

extension LauncherPanelController: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        InputTiming.shared.measure(.delegate) {
            InputTiming.shared.measure(.font) { adjustInputFontSize() }
            updateResults(query: searchField.stringValue)
        }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            cancelSelection()
            return true
        }
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            // Return activates the selected allowed result.
            confirmSelection(); return true
        }
        if commandSelector == #selector(NSResponder.insertTab(_:)) {
            moveSelection(by: 1); return true
        }
        if commandSelector == #selector(NSResponder.insertBacktab(_:)) {
            moveSelection(by: -1); return true
        }
        if commandSelector == #selector(NSResponder.moveDown(_:)) {
            moveSelection(dx: 0, dy: 1); return true
        }
        if commandSelector == #selector(NSResponder.moveUp(_:)) {
            moveSelection(dx: 0, dy: -1); return true
        }
        // Only intercept horizontal arrows when in grid mode AND a tile
        // is currently selected. Banner rows (calculator answers,
        // conversions, the trailing web search) are full-width singletons
        // — horizontal motion is meaningless there, and the user almost
        // certainly wants the keys to move the text cursor inside their
        // expression (e.g. editing the `*` in `12*7+3`). Letting the
        // field editor handle them in that state restores normal
        // text-editing behavior without giving up 2-D tile navigation
        // when the user is actually picking tiles.
        if resultsView is ResultsGridView, isTileSelected() {
            if commandSelector == #selector(NSResponder.moveLeft(_:)) {
                moveSelection(dx: -1, dy: 0); return true
            }
            if commandSelector == #selector(NSResponder.moveRight(_:)) {
                moveSelection(dx: 1, dy: 0); return true
            }
        }
        return false
    }

    /// True when the currently-selected result is a grid tile rather than
    /// a banner row. Banners are emitted with a `.copy` action (calc /
    /// conversion answers) or as the `.url` web-search fallback whose
    /// title starts with "Search ". Everything else lives in the tile
    /// area and supports 2-D navigation.
    private func isTileSelected() -> Bool {
        guard let result = resultsView.result(at: selectedIndex) else { return false }
        switch result.action {
        case .copy:
            return false
        case .url:
            return !result.title.hasPrefix("Search ")
        default:
            return true
        }
    }
}
