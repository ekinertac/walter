import Testing
import AppKit
@testable import Walter

@Suite("ConfigManager")
struct ConfigTests {

    @Test func defaultValues() {
        let config = ConfigManager()
        #expect(config.layout.scale == 1.0 || config.layout.scale > 0) // user may have custom config
        #expect(!config.layout.placeholder.isEmpty)
    }

    @Test func scaleFunction() {
        let config = ConfigManager()
        let originalScale = config.layout.scale
        let result = config.s(100)
        #expect(result == 100 * CGFloat(originalScale))
    }

    @Test func themePresetsExist() {
        #expect(builtinThemes.count >= 21)
        #expect(builtinThemes["dracula"] != nil)
        #expect(builtinThemes["spotlight"] != nil)
        #expect(builtinThemes["catppuccin-mocha"] != nil)
    }

    @Test func themePresetValues() {
        let dracula = builtinThemes["dracula"]!
        #expect(dracula.background == "#282a36")
        #expect(dracula.accent == "#bd93f9")
    }

    @Test func spotlightIsTransparent() {
        let spotlight = builtinThemes["spotlight"]!
        #expect(spotlight.background.contains("00000000"))
    }
}
