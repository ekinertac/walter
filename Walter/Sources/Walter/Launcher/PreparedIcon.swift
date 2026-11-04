import AppKit

/// Immutable, eagerly rendered pixel buffers. No NSImage crosses into result UI.
/// 128px covers the largest 64pt tile at Retina 2x; smaller rows downsample it.
final class PreparedIcon {
    static let pixelSize = 128
    let light: CGImage
    let dark: CGImage
    let isTemplate: Bool

    init(light: CGImage, dark: CGImage, isTemplate: Bool = false) {
        self.light = light
        self.dark = dark
        self.isTemplate = isTemplate
    }

    func bitmap(darkAppearance: Bool) -> CGImage { darkAppearance ? dark : light }

    /// Worker-only production entry point. Copy the source, draw into owned
    /// RGBA bitmap contexts, and restore all thread-local drawing state. This
    /// forces lazy/vector/icon-service preparation BEFORE main-thread publication.
    static func prepare(_ source: NSImage) -> PreparedIcon? {
        guard let image = source.copy() as? NSImage,
              image.size.width.isFinite, image.size.height.isFinite,
              image.size.width > 0, image.size.height > 0 else { return nil }
        let template = image.isTemplate
        image.isTemplate = false // Preserve the original alpha; tint templates in the view.
        image.cacheMode = .never // Do not reuse a drawing cache from the other appearance.
        guard let light = render(image, appearance: .aqua) else { return nil }
        // Template alpha is appearance-independent; colored assets may have
        // appearance-specific representations, so prepare both ahead of time.
        guard let dark = template ? light : render(image, appearance: .darkAqua) else { return nil }
        return PreparedIcon(light: light, dark: dark, isTemplate: template)
    }

    static func fittedRect(size: CGSize, in bounds: CGRect) -> CGRect {
        let scale = min(bounds.width / size.width, bounds.height / size.height)
        let fitted = CGSize(width: size.width * scale, height: size.height * scale)
        return CGRect(x: bounds.midX - fitted.width / 2, y: bounds.midY - fitted.height / 2,
                      width: fitted.width, height: fitted.height)
    }

    private static func render(_ image: NSImage, appearance name: NSAppearance.Name) -> CGImage? {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: pixelSize, height: pixelSize,
                  bitsPerComponent: 8, bytesPerRow: pixelSize * 4, space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let appearance = NSAppearance(named: name) else { return nil }
        context.interpolationQuality = .high
        let bounds = CGRect(x: 0, y: 0, width: pixelSize, height: pixelSize)
        context.clear(bounds)
        appearance.performAsCurrentDrawingAppearance {
            NSGraphicsContext.saveGraphicsState()
            defer { NSGraphicsContext.restoreGraphicsState() }
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            image.draw(in: fittedRect(size: image.size, in: bounds), from: .zero,
                       operation: .copy, fraction: 1, respectFlipped: false, hints: nil)
        }
        return context.makeImage()
    }
}
