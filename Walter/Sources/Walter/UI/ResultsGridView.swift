// ResultsGridView.swift — Grid layout alternative to ResultsListView
//
// Renders search results as icon tiles in a fixed-column grid (Spotlight-on-
// macOS-Tahoe style) instead of the default Alfred/Raycast row list. Same
// data flow as ResultsListView — LauncherPanelController calls update(...)
// with the same SearchResult array — but each item is laid out as a tile
// (large icon above the title) and selection moves in two dimensions via
// arrow keys.
//
// Computed answers (calculator / converter) and the trailing web-search
// fallback are not meaningful as icon tiles, so they render as full-width
// banner rows above and below the tile area. Banners use the same row
// styling as the list view so the layout reads naturally even in grid mode.
//
// Layout: a flipped FlippedView document inside an NSScrollView. Tiles are
// positioned manually because the count is small (≤25), the grid is
// regular, and NSCollectionView is overkill at this scale.
//
// Pivots from list mode are confined to this file plus the picker logic
// in LauncherPanelController.swift; the search engine and SearchResult
// model are unchanged.

import AppKit

class ResultsGridView: NSView, ResultsView {

    private let scrollView: NSScrollView
    private let documentView: NSView
    private var rowViews: [(NSView, Int)] = []   // (view, original-result-index)
    private var results: [SearchResult] = []
    private let config: ConfigManager

    /// Cached split of the current results between top banners (computed
    /// answers), grid tiles (apps / panes / commands / aliases / theme),
    /// and the bottom banner (web search fallback). Indices reference the
    /// original `results` array so selection state stays consistent with
    /// what LauncherPanelController hands back to the engine.
    private var topBannerIndices: [Int] = []
    private var tileIndices: [Int] = []
    private var bottomBannerIndex: Int? = nil
    private var currentSelectedIndex: Int = 0

    /// Fixed column count for now. The screenshot reference uses 5 — this
    /// matches the macOS Tahoe app launcher and gives generous tap targets.
    private let columns = 5

    /// Maximum number of tile rows visible at once (5 cols × 3 rows = 15).
    /// More than this stops feeling like a focused launcher and starts
    /// looking like a full app browser. Banners (calculator answers, web
    /// search fallback) sit above and below this region and are unaffected.
    private let maxTileRows = 3

    var onRowClicked: ((Int) -> Void)?
    var resultCount: Int { results.count }

    init(config: ConfigManager) {
        self.config = config

        scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.scrollerStyle = .overlay
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        documentView = FlippedView()
        scrollView.documentView = documentView

        super.init(frame: .zero)

        addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func result(at index: Int) -> SearchResult? {
        guard index >= 0, index < results.count else { return nil }
        return results[index]
    }

    func contentHeight(for results: [SearchResult], maxRows: Int) -> CGFloat {
        guard !results.isEmpty else { return 0 }
        let split = classify(results: results)
        let bannerHeight = config.s(64)
        let tileHeight = config.s(120)
        let topBanners = CGFloat(split.top.count) * bannerHeight
        let bottomBanner = split.bottom != nil ? bannerHeight : 0
        // tile count is already capped by classify(); maxRows from the
        // panel acts only as a further upper bound (e.g. tiny screens).
        let gridRows = split.tiles.isEmpty ? 0 : (split.tiles.count + columns - 1) / columns
        let visibleGridRows = min(gridRows, maxRows, maxTileRows)
        let tilesHeight = CGFloat(visibleGridRows) * tileHeight
        let padding = config.s(8) * 2
        return topBanners + tilesHeight + bottomBanner + padding
    }

    func step(by delta: Int, from current: Int) -> Int {
        guard !results.isEmpty else { return 0 }
        return (current + delta + results.count) % results.count
    }

    func step(dx: Int, dy: Int, from current: Int) -> Int {
        guard !results.isEmpty else { return 0 }
        if dy == 0 && dx == 0 { return current }

        // Build the visual sequence: top banners first, then tiles, then
        // bottom banner. We map between visual position and original index
        // here so selection traversal feels natural regardless of category.
        let order = visualOrder()
        guard let visualPos = order.firstIndex(of: current) else { return current }

        // dy: navigate vertically through the layout. Top banners and the
        // bottom banner each occupy one full row; the grid in between is
        // multi-row. Inside the grid we move by `columns` per dy step.
        if dy != 0 {
            // How many "rows" we need to traverse depends on whether we're
            // in a banner area or in the grid. Treat each banner as 1 row;
            // each grid row is `columns` wide.
            let target = nextVisualPosition(from: visualPos, dy: dy, order: order)
            return order[target]
        }

        if dx != 0 {
            // Horizontal motion only makes sense inside the grid; in banner
            // rows, fall through to sequential motion (one banner per row).
            let target = (visualPos + dx + order.count) % order.count
            return order[target]
        }

        return current
    }

    func update(results: [SearchResult], selectedIndex: Int) {
        self.results = results
        let split = classify(results: results)
        topBannerIndices = split.top
        tileIndices = split.tiles
        bottomBannerIndex = split.bottom
        rebuildSubviews()
        update(selectedIndex: selectedIndex)
    }

    func update(selectedIndex: Int) {
        currentSelectedIndex = selectedIndex
        for (view, index) in rowViews {
            let selected = (index == selectedIndex)
            (view as? ResultRowView)?.setSelected(selected)
            (view as? ResultTileView)?.setSelected(selected)
        }
        scrollToView(forIndex: selectedIndex)
    }

    func updateColors(foreground: NSColor, accent: NSColor) {
        for (view, _) in rowViews {
            (view as? ResultRowView)?.updateColors(foreground: foreground, accent: accent)
            (view as? ResultTileView)?.updateColors(foreground: foreground, accent: accent)
        }
    }

    // MARK: - Splitting computed answers / web fallback off the grid

    private struct ResultSplit {
        var top: [Int]
        var tiles: [Int]
        var bottom: Int?
    }

    private func classify(results: [SearchResult]) -> ResultSplit {
        var split = ResultSplit(top: [], tiles: [], bottom: nil)
        for (i, r) in results.enumerated() {
            if isComputedAnswer(r) {
                split.top.append(i)
            } else if isWebSearchFallback(r) && i == results.count - 1 {
                split.bottom = i
            } else {
                split.tiles.append(i)
            }
        }
        // Cap the tile section at maxTileRows × columns. Anything past the
        // cap is dropped from the index entirely so navigation, scrolling
        // and rendering all see a consistent slice.
        let tileCap = maxTileRows * columns
        if split.tiles.count > tileCap {
            split.tiles = Array(split.tiles.prefix(tileCap))
        }
        return split
    }

    private func isComputedAnswer(_ result: SearchResult) -> Bool {
        // Calculator + converter pin themselves as `.copy` actions.
        if case .copy = result.action { return true }
        return false
    }

    private func isWebSearchFallback(_ result: SearchResult) -> Bool {
        // Web fallback is the only `.url` action whose title starts with
        // "Search " — engine emits e.g. `Search Google for "foo"`.
        if case .url = result.action, result.title.hasPrefix("Search ") {
            return true
        }
        return false
    }

    /// Visual traversal order (top banners → tiles → bottom banner), each
    /// element is the original-results index.
    private func visualOrder() -> [Int] {
        var order = topBannerIndices + tileIndices
        if let b = bottomBannerIndex { order.append(b) }
        return order
    }

    /// Vertical move within the visual layout. Each banner counts as one
    /// row; each grid row spans `columns` tile slots. Stays within bounds.
    private func nextVisualPosition(from visualPos: Int, dy: Int, order: [Int]) -> Int {
        // Decompose into segments: [topBanners][tiles][bottomBanner]
        let topCount = topBannerIndices.count
        let tileCount = tileIndices.count
        let hasBottom = bottomBannerIndex != nil

        // Top-banner region: visualPos in [0, topCount). One row each.
        if visualPos < topCount {
            let proposed = visualPos + dy
            if proposed < 0 { return 0 }
            if proposed < topCount { return proposed }
            // Crossing into the tile area
            if tileCount > 0 { return topCount }
            // Crossing past tiles into bottom banner
            if hasBottom { return topCount + tileCount }
            return visualPos
        }

        // Tile region.
        if visualPos < topCount + tileCount {
            let tilePos = visualPos - topCount
            let row = tilePos / columns
            let col = tilePos % columns
            let totalRows = (tileCount + columns - 1) / columns
            let newRow = row + dy

            if newRow < 0 {
                if topCount > 0 { return max(0, topCount - 1) }
                // wrap into bottom banner if it exists, else stay
                if hasBottom { return topCount + tileCount }
                return visualPos
            }
            if newRow >= totalRows {
                if hasBottom { return topCount + tileCount }
                if topCount > 0 { return topCount - 1 } // wrap to last top banner
                return visualPos
            }
            // Stay inside the grid
            let candidate = topCount + min(newRow * columns + col, tileCount - 1)
            return candidate
        }

        // Bottom banner — single row.
        let proposed = visualPos + dy
        if proposed > visualPos { return visualPos }   // can't go past bottom
        if tileCount > 0 {
            // Land on the same column we came from in the last tile row.
            let lastRowStart = topCount + ((tileCount - 1) / columns) * columns
            return lastRowStart
        }
        if topCount > 0 { return topCount - 1 }
        return visualPos
    }

    // MARK: - Layout

    private func tileSize() -> NSSize {
        let sideInset = config.s(16)
        let usable = max(1, bounds.width - sideInset * 2)
        let width = floor(usable / CGFloat(columns))
        let height = config.s(120)
        return NSSize(width: width, height: height)
    }

    private func scrollToView(forIndex index: Int) {
        guard let entry = rowViews.first(where: { $0.1 == index }) else { return }
        entry.0.layoutSubtreeIfNeeded()
        let frame = entry.0.convert(entry.0.bounds, to: documentView)
        scrollView.contentView.scrollToVisible(frame)
    }

    private func rebuildSubviews() {
        rowViews.forEach { $0.0.removeFromSuperview() }
        rowViews = []

        guard !results.isEmpty else {
            documentView.frame = NSRect(x: 0, y: 0, width: bounds.width, height: 0)
            return
        }

        let tile = tileSize()
        let bannerHeight = config.s(64)
        let sideInset = config.s(16)
        let topPad = config.s(8)
        var y = topPad

        // Top banners (full width).
        for index in topBannerIndices {
            let row = ResultRowView(result: results[index], config: config)
            row.onClick = { [weak self] in self?.onRowClicked?(index) }
            row.frame = NSRect(
                x: sideInset,
                y: y,
                width: max(0, bounds.width - sideInset * 2),
                height: bannerHeight - config.s(4)
            )
            row.autoresizingMask = [.width]
            documentView.addSubview(row)
            rowViews.append((row, index))
            y += bannerHeight
        }

        // Tile grid.
        for (visualPos, index) in tileIndices.enumerated() {
            let row = visualPos / columns
            let col = visualPos % columns
            let tileView = ResultTileView(result: results[index], config: config)
            tileView.onClick = { [weak self] in self?.onRowClicked?(index) }
            tileView.frame = NSRect(
                x: sideInset + CGFloat(col) * tile.width,
                y: y + CGFloat(row) * tile.height,
                width: tile.width,
                height: tile.height
            )
            documentView.addSubview(tileView)
            rowViews.append((tileView, index))
        }
        if !tileIndices.isEmpty {
            let gridRows = (tileIndices.count + columns - 1) / columns
            y += CGFloat(gridRows) * tile.height
        }

        // Bottom banner.
        if let index = bottomBannerIndex {
            let row = ResultRowView(result: results[index], config: config)
            row.onClick = { [weak self] in self?.onRowClicked?(index) }
            row.frame = NSRect(
                x: sideInset,
                y: y,
                width: max(0, bounds.width - sideInset * 2),
                height: bannerHeight - config.s(4)
            )
            row.autoresizingMask = [.width]
            documentView.addSubview(row)
            rowViews.append((row, index))
            y += bannerHeight
        }

        documentView.frame = NSRect(x: 0, y: 0, width: bounds.width, height: y + topPad)
    }

    override func layout() {
        super.layout()
        // Width-only adjustments to existing subviews. We deliberately do
        // NOT rebuild here — `rebuildSubviews()` recreates tile views and
        // wipes `setSelected(true)` flags that were just applied during
        // `update(results:selectedIndex:)`. Layout fires asynchronously
        // after the frame settles on each keystroke, so rebuilding from
        // here introduces a race where the first-result selection
        // disappears intermittently as the user types.
        documentView.frame.size.width = scrollView.contentSize.width
        guard !rowViews.isEmpty else { return }

        let tile = tileSize()
        let sideInset = config.s(16)
        let bannerWidth = max(0, bounds.width - sideInset * 2)

        for (view, _) in rowViews {
            if view is ResultTileView {
                // Tile column = current x relative to inset, divided by tile width
                let originalCol = Int((view.frame.origin.x - sideInset) / max(1, view.frame.size.width))
                view.frame.origin.x = sideInset + CGFloat(originalCol) * tile.width
                view.frame.size.width = tile.width
            } else if view is ResultRowView {
                view.frame.origin.x = sideInset
                view.frame.size.width = bannerWidth
            }
        }

        // Re-apply the current selection so any view that drew itself
        // unselected during the bare-frame relayout flips back.
        update(selectedIndex: currentSelectedIndex)
    }
}

// MARK: - Tile

class ResultTileView: NSView {

    var onClick: (() -> Void)?

    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let highlight = CALayer()

    init(result: SearchResult, config: ConfigManager) {
        super.init(frame: .zero)
        wantsLayer = true

        let iconSize = config.s(64)
        let cornerRadius = config.s(14)

        highlight.cornerRadius = cornerRadius
        highlight.backgroundColor = nil
        layer?.addSublayer(highlight)

        if let icon = result.icon {
            icon.size = NSSize(width: iconSize, height: iconSize)
            iconView.image = icon
        }
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = LauncherPanelController.resolveFont(name: config.theme.font, size: config.s(13), weight: .medium)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.alignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.stringValue = result.title

        addSubview(iconView)
        addSubview(titleLabel)

        NSLayoutConstraint.activate([
            iconView.topAnchor.constraint(equalTo: topAnchor, constant: config.s(10)),
            iconView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconView.widthAnchor.constraint(equalToConstant: iconSize),
            iconView.heightAnchor.constraint(equalToConstant: iconSize),

            titleLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: config.s(6)),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: config.s(4)),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -config.s(4)),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    private var accentColor: NSColor = .controlAccentColor

    override func layout() {
        super.layout()
        let inset: CGFloat = 4
        highlight.frame = bounds.insetBy(dx: inset, dy: inset)
    }

    func setSelected(_ selected: Bool) {
        if selected {
            highlight.backgroundColor = accentColor.withAlphaComponent(0.25).cgColor
        } else {
            highlight.backgroundColor = nil
        }
    }

    func updateColors(foreground: NSColor, accent: NSColor) {
        titleLabel.textColor = foreground
        accentColor = accent
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    override func mouseEntered(with event: NSEvent) {
        if highlight.backgroundColor == nil {
            highlight.backgroundColor = NSColor.labelColor.withAlphaComponent(0.07).cgColor
        }
    }

    override func mouseExited(with event: NSEvent) {
        if highlight.backgroundColor != accentColor.withAlphaComponent(0.25).cgColor {
            highlight.backgroundColor = nil
        }
    }
}
