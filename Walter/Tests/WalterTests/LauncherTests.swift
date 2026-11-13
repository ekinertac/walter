import Foundation
import Testing
@testable import Walter

@Suite("Local launcher routing and mocked handoffs")
@MainActor
struct LauncherTests {
    @Test func lateSymbolPublicationIsVisibleWithoutRebuildingEngine() throws {
        let fixture = try TemporaryDirectory()
        let config = ConfigManager(configURL: fixture.file("config.toml"), watchForChanges: false)
        let icon = IconFixture.icon()
        var ready = false
        let engine = LauncherEngine(config: config, entries: { [] },
            openURL: { _ in Issue.record("Unexpected handoff") },
            symbolLoader: { _, _ in ready ? icon : nil })
        let first = engine.search(query: "a")
        #expect(first.allSatisfy { $0.icon == nil })
        ready = true
        let second = engine.search(query: "a")
        #expect(second.map(\.title) == first.map(\.title))
        #expect(second.allSatisfy { $0.icon === icon })
        #expect(engine.search(query: "").isEmpty)
        #expect(engine.search(query: "a").allSatisfy { $0.icon === icon })
    }

    @Test func computedAnswersLeadAndCopyTheirFormattedValue() throws {
        let fixture = try TemporaryDirectory()
        let config = ConfigManager(configURL: fixture.file("config.toml"), watchForChanges: false)
        let engine = LauncherEngine(config: config, entries: { [] }, locale: Locale(identifier: "en_US"), openURL: { _ in Issue.record("Unexpected handoff") })
        let result = try #require(engine.search(query: "100/7").first)
        #expect(result.title.contains("285714"))
        if case .copy(let value) = result.action { #expect(value == result.title) }
        else { Issue.record("Expected calculator copy action") }
        #expect(engine.search(query: "(").count == 1) // Only local web fallback, no math crash.
        #expect(engine.search(query: "10 km in miles").first?.title.hasSuffix(" mi") == true)
        #expect(engine.search(query: "").isEmpty)
    }

    @Test func aliasesAreEncodedAndOnlyOpenOnActivation() throws {
        let fixture = try TemporaryDirectory()
        let url = fixture.file("config.toml")
        try """
        [aliases.y]
        name = "Example Search"
        url = "https://example.invalid/?q={query}"
        """.write(to: url, atomically: true, encoding: .utf8)
        let config = ConfigManager(configURL: url, watchForChanges: false)
        var opened: [URL] = []
        let engine = LauncherEngine(config: config, entries: { [] }, locale: Locale(identifier: "en_US"), openURL: { opened.append($0) })
        let results = engine.search(query: "y cats & dogs")
        #expect(results.count == 2)
        #expect(results[0].title == "Example Search → cats & dogs")
        #expect(opened.isEmpty)
        engine.launch(result: results[0])
        #expect(opened.first?.absoluteString == "https://example.invalid/?q=cats%20%26%20dogs")
        for target in ["file:///private/tmp/file", "javascript:alert(1)", "!echo ignored"] {
            engine.launch(result: SearchResult(title: "Invalid", subtitle: "", icon: nil, action: .url(target)))
        }
        #expect(opened.count == 1)
    }

    @Test func appAliasesRevalidateAtActivation() throws {
        let fixture = try TemporaryDirectory()
        let root = fixture.file("Applications")
        let target = root.appendingPathComponent("Good.app").standardizedFileURL
        let contents = target.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist = try PropertyListSerialization.data(fromPropertyList: ["CFBundlePackageType": "APPL"], format: .xml, options: 0)
        try plist.write(to: contents.appendingPathComponent("Info.plist"))
        let url = fixture.file("config.toml")
        try "[aliases]\nfixtureapp = \"\(target.path)\"\n".write(to: url, atomically: true, encoding: .utf8)
        let policy = AllowedApps(root: root)
        let config = ConfigManager(configURL: url, watchForChanges: false, apps: policy)
        var opened: [URL] = []
        let engine = LauncherEngine(config: config, entries: { [] }, apps: policy, locale: Locale(identifier: "en_US"), openURL: { opened.append($0) })
        let result = try #require(engine.search(query: "fixtureapp").first)
        if case .openApp = result.action {} else { Issue.record("Expected app alias") }
        engine.launch(result: result)
        #expect(opened.map(\.path) == [target.standardizedFileURL.path])
        try FileManager.default.removeItem(at: target)
        engine.launch(result: result)
        #expect(opened.count == 1)
    }

    @Test func appExclusionsMatchNamesOrFullPathsAndReload() throws {
        let fixture = try TemporaryDirectory()
        let url = fixture.file("config.toml")
        try "[search]\nexcluded_apps = [\"/system/applications/news.APP\", \"cAlEnDaR\"]\n".write(to: url, atomically: true, encoding: .utf8)
        let config = ConfigManager(configURL: url, watchForChanges: false)
        let paths = ["/System/Applications/News.app", "/Applications/News.app", "/Applications/Calendar.app"]
        let entries = paths.map { path in
            let name = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
            return AppEntry(name: name, path: path, nameLower: name.lowercased(), icon: nil)
        }
        let engine = LauncherEngine(config: config, entries: { entries },
            openURL: { _ in Issue.record("Unexpected handoff") })
        func appPaths(_ query: String) -> [String] {
            engine.search(query: query).compactMap {
                if case .openApp(let path) = $0.action { return path }
                return nil
            }
        }
        #expect(appPaths("news") == ["/Applications/News.app"])
        #expect(appPaths("calendar").isEmpty)
        // An exclusion is not a prefix/folder match.
        config.search.excludedApps = ["/System/Applications"]
        #expect(Set(appPaths("news")) == Set(paths.prefix(2)))
        try "[search]\n".write(to: url, atomically: true, encoding: .utf8)
        config.reload()
        #expect(Set(appPaths("news")) == Set(paths.prefix(2)))
        #expect(appPaths("calendar") == ["/Applications/Calendar.app"])
    }

    @Test func fuzzyRankingSettingsAndThemesRemain() throws {
        let fixture = try TemporaryDirectory()
        let config = ConfigManager(configURL: fixture.file("config.toml"), watchForChanges: false)
        let entries = ["Calculator", "Calendar"].map { AppEntry(name: $0, path: "/Applications/\($0).app", nameLower: $0.lowercased(), icon: nil) }
        var opened: [URL] = []
        let engine = LauncherEngine(config: config, entries: { entries }, locale: Locale(identifier: "en_US"), openURL: { opened.append($0) })
        #expect(engine.search(query: "calculator").first?.title == "Calculator")
        config.search.excludedApps = ["Calculator"]
        #expect(!engine.search(query: "calculator").contains(where: { $0.title == "Calculator" }))
        let settings = try #require(engine.search(query: "Bluetooth").first(where: { $0.title == "Bluetooth" }))
        engine.launch(result: settings)
        #expect(opened.first?.scheme == "x-apple.systempreferences")
        engine.launch(result: SearchResult(title: "Invalid", subtitle: "", icon: nil, action: .settings("file:///private/tmp")))
        #expect(opened.count == 1)
        #expect(engine.themeResults(filter: "example").contains(where: { $0.title == "Example" }))
        #expect(engine.search(query: "change theme").first?.title == "Change Theme")
    }
}
