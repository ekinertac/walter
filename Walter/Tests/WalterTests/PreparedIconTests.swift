import AppKit
import Testing
@testable import Walter

@Suite("Eager icon preparation (in-memory offscreen drawing, no views)")
struct PreparedIconTests {
    @Test func rasterizationOwnsPixelsPreservesAspectAndDoesNotMutateSource() async throws {
        let icon = await Task.detached {
            autoreleasepool {
                let source = NSImage(cgImage: IconFixture.bitmap(), size: NSSize(width: 20, height: 10))
                let result = PreparedIcon.prepare(source)
                #expect(source.size == NSSize(width: 20, height: 10))
                #expect(!source.isTemplate)
                return result
            }
        }.value
        let prepared = try #require(icon)
        #expect(prepared.light.width == 128)
        #expect(prepared.light.height == 128)
        #expect(prepared.dark.width == 128)
        #expect(!prepared.isTemplate)
        let bytes = try #require(prepared.light.dataProvider?.data)
        let data = Array(bytes as Data)
        // RGBA, centered 2:1 image in a transparent square. No lazy NSImage
        // representation is required to read these already-rendered pixels.
        #expect(data[64 * 4 + 3] == 0)
        let center = 64 * prepared.light.bytesPerRow + 64 * 4
        #expect(data[center] > 240)
        #expect(data[center + 1] < 10)
        #expect(data[center + 3] == 255)
    }

    @Test func templateAlphaIsSharedAndSourceTemplateFlagIsUnchanged() async throws {
        let icon = await Task.detached {
            autoreleasepool {
                let source = NSImage(cgImage: IconFixture.bitmap(), size: NSSize(width: 20, height: 10))
                source.isTemplate = true
                let result = PreparedIcon.prepare(source)
                #expect(source.isTemplate)
                return result
            }
        }.value
        let prepared = try #require(icon)
        #expect(prepared.isTemplate)
        #expect(prepared.light === prepared.dark)
    }

    @Test func lazyDrawingHappensOnWorkerAndRestoresContextAndAppearance() async throws {
        let icon = await Task.detached {
            autoreleasepool {
                let before = NSGraphicsContext.current
                let appearanceBefore = NSAppearance.currentDrawing()
                var draws = 0
                let source = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { bounds in
                    #expect(!Thread.isMainThread)
                    draws += 1
                    let dark = NSAppearance.currentDrawing().bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                    (dark ? NSColor.blue : NSColor.red).setFill()
                    bounds.fill()
                    return true
                }
                let result = PreparedIcon.prepare(source)
                #expect(draws >= 2)
                #expect(NSGraphicsContext.current === before)
                #expect(NSAppearance.currentDrawing() === appearanceBefore)
                return result
            }
        }.value
        let prepared = try #require(icon)
        let light = Array(try #require(prepared.light.dataProvider?.data) as Data)
        let dark = Array(try #require(prepared.dark.dataProvider?.data) as Data)
        #expect(light[0] > 240 && light[2] < 10)
        #expect(dark[2] > 240 && dark[0] < 10)
        #expect(prepared.bitmap(darkAppearance: false) === prepared.light)
        #expect(prepared.bitmap(darkAppearance: true) === prepared.dark)
    }

    @Test func fittedRectAndInvalidSourceSize() {
        let rect = PreparedIcon.fittedRect(size: CGSize(width: 20, height: 10),
                                          in: CGRect(x: 0, y: 0, width: 128, height: 128))
        #expect(rect == CGRect(x: 0, y: 32, width: 128, height: 64))
        #expect(PreparedIcon.prepare(NSImage(size: .zero)) == nil)
    }
}
