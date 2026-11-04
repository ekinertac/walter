import Foundation
import Testing
@testable import Walter

@Suite("Isolated configuration")
struct ConfigTests {
    @Test func defaultsAndThemes() throws {
        let fixture = try TemporaryDirectory()
        let config = ConfigManager(configURL: fixture.file("config.toml"), watchForChanges: false)
        #expect(ConfigManager.Keybindings().open == "Cmd+Space")
        #expect(config.keybindings.open == "Cmd+Space")
        #expect(config.layout.width == 780)
        #expect(config.layout.mode == "list")
        #expect(config.layout.maxResults == 8)
        #expect(config.layout.placeholder == "Search apps, calculate, convert...")
        #expect(config.userThemesDir == fixture.file("themes"))
        #expect(config.userThemes["example"]?.background == "#1a1a2e")
        #expect(builtinThemes.count == 21)
        #expect(builtinThemes["dracula"]?.accent == "#bd93f9")
        let defaults = try String(contentsOf: config.configURL, encoding: .utf8)
        #expect(defaults.contains("open = \"Cmd+Space\""))
        for removed in ["favicon_service", "file_dirs", "file_prefix", "app_dirs", "show_system_commands", "scale =", "position =", "[general]"] {
            #expect(!defaults.contains(removed))
        }
    }

    @Test func quotedAppHotkeysPreserveDuplicatesAndReload() throws {
        let fixture = try TemporaryDirectory()
        let url = fixture.file("config.toml")
        try """
        [app_hotkeys]
        "Cmd+Ctrl+t" = "/Applications/kitty.app" # comment
        "Cmd+Ctrl+t" = "/Applications/Other.app"
        “Ctrl+Shift+k” = “/Applications/With # and =.app”
        """.write(to: url, atomically: true, encoding: .utf8)
        let config = ConfigManager(configURL: url, watchForChanges: false)
        #expect(config.appHotkeyErrors.isEmpty)
        #expect(config.appHotkeys.map(\.binding) == ["Cmd+Ctrl+t", "Cmd+Ctrl+t", "Ctrl+Shift+k"])
        #expect(config.appHotkeys.last?.path == "/Applications/With # and =.app")
        config.selectTheme("dracula")
        config.reload()
        #expect(config.appHotkeys.count == 3)
        try "[app_hotkeys]\n".write(to: url, atomically: true, encoding: .utf8)
        config.reload()
        #expect(config.appHotkeys.isEmpty)
        #expect(config.appHotkeyErrors.isEmpty)
    }

    @Test(arguments: [
        "Cmd+T = \"/Applications/Test.app\"",
        "\"Cmd+T\" = /Applications/Test.app",
        "\"Cmd+T\" = \"/Applications/Test.app",
        "\"Cmd+T\" = \"/Applications/Test.app\" trailing",
        "\"Cmd+T\"",
        "\"Cmd+T\" = \"/Applications/Back\\\\slash.app\""
    ])
    func malformedAppHotkeysReported(line: String) throws {
        let fixture = try TemporaryDirectory()
        let url = fixture.file("config.toml")
        try "[app_hotkeys]\n\(line)\n".write(to: url, atomically: true, encoding: .utf8)
        let config = ConfigManager(configURL: url, watchForChanges: false)
        #expect(config.appHotkeys.isEmpty)
        #expect(config.appHotkeyErrors.count == 1)
        try "[app_hotkeys]\n".write(to: url, atomically: true, encoding: .utf8)
        config.reload()
        #expect(config.appHotkeyErrors.isEmpty)
    }

    @Test func removedSettingsIgnoredAndReloadIsLocal() throws {
        let fixture = try TemporaryDirectory()
        let url = fixture.file("config.toml")
        try """
        [layout]
        scale = 4
        position = "top"
        mode = “grid” # smart quotes
        [keybindings]
        open = "Alt+Space"
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
        #expect(config.keybindings.open == "Alt+Space") // Preserve existing custom bindings.
        #expect(config.layout.mode == "grid")
        #expect(config.s(100) == 100)
        #expect(config.aliases["example"] == "https://example.invalid/{query}")
        #expect(!FileManager.default.fileExists(atPath: fixture.file(".cache").path))
        try "[layout]\nplaceholder = \"Reloaded\"\n".write(to: url, atomically: true, encoding: .utf8)
        config.reload()
        #expect(config.layout.placeholder == "Reloaded")
        #expect(config.keybindings.open == "Cmd+Space") // Missing setting uses the default.
        #expect(config.aliases.isEmpty)
    }

    @Test func rejectsLegacyCommandsAndArbitraryPaths() throws {
        let fixture = try TemporaryDirectory()
        let url = fixture.file("config.toml")
        try """
        [aliases]
        flat = "!echo ignored"
        spaced = "  !echo {query}"
        file = "/private/tmp/file.txt"
        badApp = "/NotAnAllowedRoot/Test.app"
        fileURL = "file:///private/tmp/file.txt"
        scheme = "javascript:alert(1)"
        good = "https://example.invalid/{query}"
        [aliases.named]
        name = "Legacy command"
        url = "!echo {query}"
        [aliases.legacyValue]
        value = "!https://example.invalid"
        [aliases.legacyPath]
        path = "!/Applications/Test.app"
        [aliases.commandKey]
        cmd = "echo ignored"
        """.write(to: url, atomically: true, encoding: .utf8)
        let config = ConfigManager(configURL: url, watchForChanges: false)
        #expect(config.aliases == ["good": "https://example.invalid/{query}"])
        try "[aliases]\ngood = \"!echo replaced\"\n".write(to: url, atomically: true, encoding: .utf8)
        config.reload()
        #expect(config.aliases.isEmpty)
    }

    @Test func themeRoundTripPreservesOtherSections() throws {
        let fixture = try TemporaryDirectory()
        let config = ConfigManager(configURL: fixture.file("config.toml"), watchForChanges: false)
        config.selectTheme("dracula")
        config.reload()
        #expect(config.theme.name == "dracula")
        #expect(config.theme.background == "#282a36")
        config.selectTheme("example")
        config.reload()
        #expect(config.theme.background == "#1a1a2e")
        #expect(config.layout.width == 780)
        let before = try String(contentsOf: config.configURL, encoding: .utf8)
        config.selectTheme("not-a-theme\n[aliases]")
        #expect(try String(contentsOf: config.configURL, encoding: .utf8) == before)
    }

    @MainActor @Test func hotReloadStopsReliably() async throws {
        let fixture = try TemporaryDirectory()
        let config = ConfigManager(configURL: fixture.file("config.toml"))
        defer { config.stopWatching() }
        var reloads = 0
        config.onChange = { reloads += 1 }
        try "[layout]\nplaceholder = \"Watched\"\n".write(to: config.configURL, atomically: true, encoding: .utf8)
        for _ in 0..<40 {
            if config.layout.placeholder == "Watched" { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        #expect(config.layout.placeholder == "Watched")
        try "background #111111\nforeground #eeeeee\naccent #abcdef\nselection #222222\n".write(
            to: config.userThemesDir.appendingPathComponent("fresh.theme"), atomically: true, encoding: .utf8
        )
        for _ in 0..<40 {
            if config.userThemes["fresh"] != nil { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        #expect(config.userThemes["fresh"]?.accent == "#abcdef")
        #expect(config.userThemes["fresh"]?.selection == "#222222")
        config.stopWatching()
        let stoppedAt = reloads
        try "[layout]\nplaceholder = \"Stopped\"\n".write(to: config.configURL, atomically: true, encoding: .utf8)
        try await Task.sleep(nanoseconds: 300_000_000)
        #expect(reloads == stoppedAt)
        #expect(config.layout.placeholder == "Watched")
    }
}
