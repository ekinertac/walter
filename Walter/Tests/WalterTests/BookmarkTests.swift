import Foundation
import Testing
@testable import Walter

@Suite("Bookmarks: isolated config and mocked browser handoffs")
@MainActor
struct BookmarkTests {
    @Test func defaultsAreEmpty() throws {
        let fixture = try TemporaryDirectory()
        let config = ConfigManager(configURL: fixture.file("config.toml"), watchForChanges: false,
                                   apps: AllowedApps(roots: []))
        #expect(config.bookmarks.isEmpty)
        #expect(ConfigManager.defaultConfig.contains("[bookmarks]"))
    }

    @Test func quotedKeywordsValidationAndReload() throws {
        let fixture = try TemporaryDirectory()
        let url = fixture.file("config.toml")
        try """
        [bookmarks]
        " Google " = "https://old.invalid"
        "GOOGLE" = "https://example.invalid/?a=1&b=2#fragment" # comment
        “docs” = “http://docs.invalid/path”
        "" = "https://empty.invalid"
        "   " = "https://empty.invalid"
        "file" = "file:///private/tmp/file"
        "app" = "/Applications/Example.app"
        "command" = "!echo ignored"
        "script" = "javascript:alert(1)"
        "missinghost" = "https://"
        "template" = "https://example.invalid/{query}"
        "replaced" = "https://example.invalid"
        "REPLACED" = "file:///private/tmp/file"
        unquoted = "https://example.invalid"
        "unquotedvalue" = https://example.invalid
        "trailing" = "https://example.invalid" garbage
        "unterminated" = "https://example.invalid
        [aliases]
        existing = "https://alias.invalid"
        """.write(to: url, atomically: true, encoding: .utf8)
        let config = ConfigManager(configURL: url, watchForChanges: false, apps: AllowedApps(roots: []))
        #expect(config.bookmarks == ["google": "https://example.invalid/?a=1&b=2#fragment",
                                     "docs": "http://docs.invalid/path"])
        #expect(config.aliases == ["existing": "https://alias.invalid"])
        config.selectTheme("dracula")
        config.reload()
        #expect(config.bookmarks.count == 2)
        try "[bookmarks]\n\"new\" = \"https://new.invalid\"\n".write(to: url, atomically: true, encoding: .utf8)
        config.reload()
        #expect(config.bookmarks == ["new": "https://new.invalid"])
        try "[search]\nshow_path = false\n".write(to: url, atomically: true, encoding: .utf8)
        config.reload()
        #expect(config.bookmarks.isEmpty)
    }

    @Test func fuzzyRankingCachedIndicatorAndActivation() throws {
        let fixture = try TemporaryDirectory()
        let url = fixture.file("config.toml")
        try """
        [bookmarks]
        "google" = "https://example.invalid/?a=1&b=2#fragment"
        "google maps" = "https://maps.invalid"
        """.write(to: url, atomically: true, encoding: .utf8)
        let config = ConfigManager(configURL: url, watchForChanges: false, apps: AllowedApps(roots: []))
        let icon = IconFixture.icon()
        var opened: [URL] = []
        let entries = [AppEntry(name: "Google Chrome", path: "/unused/Chrome.app",
                                nameLower: "google chrome", icon: nil)]
        let engine = LauncherEngine(config: config, entries: { entries }, apps: AllowedApps(roots: []),
            openURL: { opened.append($0) },
            symbolLoader: { name, description in
                name == "bookmark" && description == "Bookmark" ? icon : nil
            })
        #expect(engine.search(query: "").isEmpty)
        let results = engine.search(query: "GOOGLE")
        let result = try #require(results.first)
        #expect(result.title == "google")
        #expect(result.subtitle == "https://example.invalid/?a=1&b=2#fragment")
        #expect(result.icon === icon)
        #expect(results.contains { $0.title == "Google Chrome" })
        #expect(results.last?.title.hasPrefix("Search ") == true)
        #expect(engine.search(query: "ggl").contains { $0.title == "google" })
        #expect(engine.search(query: "unmatchedzzzz").count == 1)
        #expect(opened.isEmpty)
        if case .url(let target) = result.action { #expect(target == result.subtitle) }
        else { Issue.record("Expected browser URL action") }
        engine.launch(result: result)
        #expect(opened.map(\.absoluteString) == [result.subtitle])
    }

    @Test func hotReloadUpdatesExistingEngineWithoutHandoff() async throws {
        let fixture = try TemporaryDirectory()
        let url = fixture.file("config.toml")
        let config = ConfigManager(configURL: url, apps: AllowedApps(roots: []))
        defer { config.stopWatching() }
        let engine = LauncherEngine(config: config, entries: { [] }, apps: AllowedApps(roots: []),
                                    openURL: { _ in Issue.record("Reload/search must not open browser") })
        try "[bookmarks]\n\"google\" = \"https://example.invalid\"\n".write(to: url, atomically: true, encoding: .utf8)
        for _ in 0..<80 {
            if config.bookmarks["google"] != nil { break }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        #expect(engine.search(query: "google").first?.title == "google")
        try "[bookmarks]\n".write(to: url, atomically: true, encoding: .utf8)
        for _ in 0..<80 {
            if config.bookmarks.isEmpty { break }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        #expect(config.bookmarks.isEmpty)
        #expect(!engine.search(query: "google").contains { $0.title == "google" })
    }
}
