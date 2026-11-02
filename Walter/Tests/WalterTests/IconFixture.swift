import CoreGraphics
@testable import Walter

/// Owned in-memory pixels only: no native icons, system symbols, views or files.
enum IconFixture {
    static func bitmap() -> CGImage {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(data: nil, width: 2, height: 1, bitsPerComponent: 8,
            bytesPerRow: 8, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(colorSpace: space, components: [1, 0, 0, 1])!)
        context.fill(CGRect(x: 0, y: 0, width: 2, height: 1))
        return context.makeImage()!
    }

    static func icon() -> PreparedIcon {
        let image = bitmap()
        return PreparedIcon(light: image, dark: image)
    }
}
