// ResultsListView.swift — Scrollable result list with keyboard-following selection
//
// Wraps rows in an NSScrollView so the list scrolls when the selection moves
// beyond the visible area. The scroll view is borderless and transparent to
// blend with the vibrancy background.

import AppKit

class ResultsListView: NSView {

    private let scrollView: NSScrollView
    private let documentView: NSView
    private var rowViews: [ResultRowView] = []
    private var results: [SearchResult] = []
    private let config: ConfigManager

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

    func update(results: [SearchResult], selectedIndex: Int) {
        self.results = results
        rebuildRows()
        update(selectedIndex: selectedIndex)
    }

    func update(selectedIndex: Int) {
        for (i, row) in rowViews.enumerated() {
            row.setSelected(i == selectedIndex)
        }
        scrollToRow(at: selectedIndex)
    }

    private func scrollToRow(at index: Int) {
        guard index >= 0, index < rowViews.count else { return }
        let row = rowViews[index]
        // Convert row frame to the document view's coordinate space and scroll to it
        row.layoutSubtreeIfNeeded()
        let rowFrame = row.convert(row.bounds, to: documentView)
        scrollView.contentView.scrollToVisible(rowFrame)
    }

    private func rebuildRows() {
        rowViews.forEach { $0.removeFromSuperview() }
        rowViews = []

        let rowHeight = config.s(60)
        let rowStride = config.s(64)
        let padding = config.s(4)
        let sideInset = config.s(8)

        // Show ALL results (not limited to maxResults) — the scroll view handles overflow
        let visibleResults = results

        let totalHeight = padding + CGFloat(visibleResults.count) * rowStride + padding

        // Set the document view size so the scroll view knows the content height
        documentView.frame = NSRect(x: 0, y: 0, width: bounds.width, height: totalHeight)

        // Build rows top-down. In flipped coordinates (NSScrollView uses flipped),
        // we lay out from y=0 downward.
        var yOffset = padding

        for result in visibleResults {
            let row = ResultRowView(result: result, config: config)
            row.frame = NSRect(
                x: sideInset,
                y: yOffset,
                width: max(0, documentView.bounds.width - sideInset * 2),
                height: rowHeight
            )
            row.autoresizingMask = [.width]
            documentView.addSubview(row)
            rowViews.append(row)
            yOffset += rowStride
        }
    }

    override func layout() {
        super.layout()
        // Update document view width when the parent resizes
        documentView.frame.size.width = scrollView.contentSize.width
        for row in rowViews {
            row.frame.size.width = max(0, documentView.bounds.width - config.s(8) * 2)
        }
    }
}

// MARK: - Flipped document view (so rows lay out top-to-bottom)

class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

// MARK: - Result row

class ResultRowView: NSView {

    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")

    init(result: SearchResult, config: ConfigManager) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = config.s(10)

        let iconSize = config.s(40)

        if let icon = result.icon {
            icon.size = NSSize(width: iconSize, height: iconSize)
            iconView.image = icon
        }
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .systemFont(ofSize: config.s(15), weight: .medium)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail

        subtitleLabel.font = .systemFont(ofSize: config.s(12), weight: .regular)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.lineBreakMode = .byTruncatingMiddle

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(iconView)
        addSubview(titleLabel)
        addSubview(subtitleLabel)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: config.s(12)),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: iconSize),
            iconView.heightAnchor.constraint(equalToConstant: iconSize),

            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: config.s(10)),
            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: config.s(14)),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -config.s(16)),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: config.s(2)),
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
        ])

        titleLabel.stringValue = result.title
        subtitleLabel.stringValue = result.subtitle
    }

    required init?(coder: NSCoder) { fatalError() }

    func setSelected(_ selected: Bool) {
        if selected {
            layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.2).cgColor
        } else {
            layer?.backgroundColor = nil
        }
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

    override func mouseEntered(with event: NSEvent) {
        if layer?.backgroundColor == nil {
            layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.05).cgColor
        }
    }

    override func mouseExited(with event: NSEvent) {
        if layer?.backgroundColor != NSColor.controlAccentColor.withAlphaComponent(0.2).cgColor {
            layer?.backgroundColor = nil
        }
    }
}
