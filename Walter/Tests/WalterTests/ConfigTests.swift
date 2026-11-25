import Testing
import AppKit
@testable import Walter

@Suite("ConfigManager", .serialized)
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

    /// Sets WALTER_CONFIG, which is process-wide. The suite is serialized
    /// because a parallel `ConfigManager()` would write its default template
    /// into this test's file.
    @Test func qwokPrefixParsing() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("walter-config-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("config.toml")
        let previous = ProcessInfo.processInfo.environment["WALTER_CONFIG"]
        setenv("WALTER_CONFIG", file.path, 1)
        defer {
            if let previous { setenv("WALTER_CONFIG", previous, 1) } else { unsetenv("WALTER_CONFIG") }
            try? FileManager.default.removeItem(at: dir)
        }

        for (line, expected) in [("qwok_prefix = \"dev x\"", "dev"), ("qwok_prefix = \"\"", ""), ("", "qwok")] {
            try "[search]\n\(line)\n".write(to: file, atomically: true, encoding: .utf8)
            #expect(ConfigManager().search.qwokPrefix == expected)
        }
    }
}
