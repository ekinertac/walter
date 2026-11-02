import Foundation
import Testing
@testable import Walter

@Suite("Isolated configuration")
struct ConfigTests {
    @Test func defaultsAndThemes() throws {
        let fixture = try TemporaryDirectory()
        let config = ConfigManager(configURL: fixture.file("config.toml"), watchForChanges: false)
        #expect(config.layout.width == 780)
        #expect(config.layout.mode == "list")
        #expect(config.layout.maxResults == 8)
        #expect(config.layout.placeholder == "Search apps, calculate, convert...")
        #expect(config.userThemesDir == fixture.file("themes"))
        #expect(builtinThemes.count == 21)
        #expect(builtinThemes["dracula"]?.accent == "#bd93f9")
        let defaults = try String(contentsOf: config.configURL, encoding: .utf8)
        for removed in ["favicon_service", "file_dirs", "file_prefix", "app_dirs", "show_system_commands", "scale =", "position =", "[general]"] {
            #expect(!defaults.contains(removed))
        }
    }

    @Test func removedSettingsIgnoredAndReloadIsLocal() throws {
        let fixture = try TemporaryDirectory()
        let url = fixture.file("config.toml")
        try """
        [layout]
        scale = 4
        position = "top"
        mode = “grid” # smart quotes
        [search]
        favicon_service = "https://unused.invalid/{host}"
        file_dirs = /not-scanned
        file_prefix = "!"
        app_dirs = /not-scanned
        show_system_commands = true
        web_search = "duckduckgo"
        [general]
        editor = "/not-launched"
        [aliases]
        example = "https://example.invalid/{query}"
        """.write(to: url, atomically: true, encoding: .utf8)
        let config = ConfigManager(configURL: url, watchForChanges: false)
        #expect(config.search.webSearch == "duckduckgo")
        #expect(config.layout.mode == "grid")
        #expect(config.s(100) == 100)
        #expect(config.aliases["example"] == "https://example.invalid/{query}")
        #expect(!FileManager.default.fileExists(atPath: fixture.file(".cache").path))
        try "[layout]\nplaceholder = \"Reloaded\"\n".write(to: url, atomically: true, encoding: .utf8)
        config.reload()
        #expect(config.layout.placeholder == "Reloaded")
        #expect(config.aliases.isEmpty)
    }

}
