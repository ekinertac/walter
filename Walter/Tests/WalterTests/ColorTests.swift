import AppKit
import Testing
@testable import Walter

struct ColorTests {
    @Test func localHexColorsIncludeTransparentThemes() throws {
        #expect(try #require(NSColor(hex: "#00000000")).alphaComponent == 0)
        #expect(try #require(NSColor(hex: "#ffffff")).alphaComponent == 1)
        #expect(abs(try #require(NSColor(hex: "#ff000080")).alphaComponent - 128.0/255) < 1e-12)
        #expect(NSColor(hex: "#12345") == nil)
        #expect(NSColor(hex: "#gggggg") == nil)
        #expect(NSColor(hex: "#fff#fff") == nil)
    }
}
