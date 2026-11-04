import AppKit

/// Fixed-size presentation only: no image lookup, decoding, NSImageView, or
/// intrinsic-size changes. Layer updates (including clearing) never animate.
final class ResultIconView: NSView {
    private var icon: PreparedIcon?
    private var label: String?
    private let pixels = CALayer()
    private let templateFill = CALayer()
    private let templateMask = CALayer()

    override var wantsUpdateLayer: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        pixels.contentsGravity = .resizeAspect
        pixels.minificationFilter = .linear
        pixels.magnificationFilter = .linear
        templateMask.contentsGravity = .resizeAspect
        templateMask.minificationFilter = .linear
        templateFill.mask = templateMask
        // A permanent layer graph: updateLayer only changes contents/colors,
        // never geometry or layer membership. AppKit cannot replace our pixels
        // with an empty drawRect backing store.
        layer?.addSublayer(pixels)
        layer?.addSublayer(templateFill)
        templateFill.isHidden = true
        setAccessibilityElement(false)
        setAccessibilityRole(.image)
    }

    required init?(coder: NSCoder) { fatalError() }

    func setIcon(_ value: PreparedIcon?, description: String? = nil) {
        let changed = icon !== value
        let hadIcon = icon != nil
        icon = value
        let nextLabel = value == nil ? nil : description
        if label != nextLabel {
            label = nextLabel
            setAccessibilityLabel(nextLabel)
        }
        if hadIcon != (value != nil) { setAccessibilityElement(value != nil) }
        if changed { applyBitmap() }
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        pixels.frame = bounds
        templateFill.frame = bounds
        templateMask.frame = templateFill.bounds
        CATransaction.commit()
    }

    override func updateLayer() { applyBitmap() }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyBitmap()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        applyBitmap()
    }

    private func applyBitmap() {
        guard let layer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let scale = window?.backingScaleFactor ?? 2
        layer.contentsScale = scale
        pixels.contentsScale = scale
        templateMask.contentsScale = scale
        guard let icon else {
            pixels.contents = nil
            templateMask.contents = nil
            templateFill.backgroundColor = nil
            templateFill.isHidden = true
            return
        }
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        templateFill.isHidden = !icon.isTemplate
        if icon.isTemplate {
            pixels.contents = nil
            templateMask.contents = icon.light
            effectiveAppearance.performAsCurrentDrawingAppearance {
                templateFill.backgroundColor = NSColor.labelColor.cgColor
            }
        } else {
            templateMask.contents = nil
            templateFill.backgroundColor = nil
            pixels.contents = icon.bitmap(darkAppearance: dark)
        }
    }
}
