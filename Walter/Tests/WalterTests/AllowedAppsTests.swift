import Foundation
import Testing
@testable import Walter

@Suite("Allowed application boundaries")
struct AllowedAppsTests {
    // Synthetic bundles only. Never enumerate /Applications or invoke NSWorkspace.
    private func app(_ relative: String, under root: URL) throws -> URL {
        let url = root.appendingPathComponent(relative)
        let contents = url.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist = try PropertyListSerialization.data(fromPropertyList: ["CFBundlePackageType": "APPL", "CFBundleName": "Fixture"], format: .xml, options: 0)
        try plist.write(to: contents.appendingPathComponent("Info.plist"))
        return url.standardizedFileURL
    }

    private func appRoots(in fixture: TemporaryDirectory) throws -> [URL] {
        try ["Applications", "System/Applications"].map { relative in
            let url = fixture.file(relative)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url.standardizedFileURL
        }
    }

    @Test func twoRootsShareDiscoveryAndKeepIndependentBoundaries() throws {
        #expect(AllowedApps.defaultRootPaths == ["/Applications", "/System/Applications"])
        let fixture = try TemporaryDirectory()
        let roots = try appRoots(in: fixture)
        let userApp = try app("User.app", under: roots[0])
        let systemApp = try app("Utilities/System.app", under: roots[1])
        let outside = try app("Outside.app", under: fixture.url)
        let sibling = try app("System/Applications-other/Sibling.app", under: fixture.url)
        let helper = try app("Utilities/System.app/Contents/Helper.app", under: roots[1])
        let insideAlias = roots[1].appendingPathComponent("Alias.app")
        try FileManager.default.createSymbolicLink(at: insideAlias, withDestinationURL: systemApp)
        let escape = roots[1].appendingPathComponent("Escape.app")
        try FileManager.default.createSymbolicLink(at: escape, withDestinationURL: outside)
        let crossRoot = roots[0].appendingPathComponent("CrossRoot.app")
        try FileManager.default.createSymbolicLink(at: crossRoot, withDestinationURL: systemApp)
        let policy = AllowedApps(roots: roots)
        #expect(Set(policy.discover().map(\.path)) == Set([userApp.path, systemApp.path]))
        #expect(policy.validatedURL(for: insideAlias.path)?.path == systemApp.path)
        for rejected in [outside, sibling, helper, escape, crossRoot] {
            #expect(policy.validatedURL(for: rejected.path) == nil)
        }
        // Root directories themselves must not become symlink escape routes.
        let linkedRoot = fixture.file("LinkedApplications")
        try FileManager.default.createSymbolicLink(at: linkedRoot, withDestinationURL: roots[1])
        #expect(AllowedApps(roots: [roots[0], linkedRoot]).validatedURL(
            for: linkedRoot.appendingPathComponent("Utilities/System.app").path) == nil)
        // Metadata is subject to the same root boundary as the bundle itself.
        let info = systemApp.appendingPathComponent("Contents/Info.plist")
        try FileManager.default.removeItem(at: info)
        try FileManager.default.createSymbolicLink(at: info, withDestinationURL: outside.appendingPathComponent("Contents/Info.plist"))
        #expect(policy.validatedURL(for: systemApp.path) == nil)
        #expect(policy.discover().map(\.path) == [userApp.path])
        #expect(AllowedApps(roots: []).discover().isEmpty)
    }

    @MainActor @Test func bothRootsSupportSearchAliasesHotkeysAndRevalidatedHandoffs() throws {
        let fixture = try TemporaryDirectory()
        let roots = try appRoots(in: fixture)
        let userApp = try app("User.app", under: roots[0])
        let systemApp = try app("Utilities/System.app", under: roots[1])
        let policy = AllowedApps(roots: roots)
        let url = fixture.file("config.toml")
        try """
        [keybindings]
        open = "Ctrl+Space"
        [aliases]
        useralias = "\(userApp.path)"
        sysalias = "\(systemApp.path)"
        [app_hotkeys]
        "Cmd+t" = "\(userApp.path)"
        "Cmd+k" = "\(systemApp.path)"
        """.write(to: url, atomically: true, encoding: .utf8)
        let config = ConfigManager(configURL: url, watchForChanges: false, apps: policy)
        #expect(config.aliases == ["useralias": userApp.path, "sysalias": systemApp.path])
        var opened: [URL] = []
        let utilities = roots[1].appendingPathComponent("Utilities")
        #expect(try utilities.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true)
        #expect(try utilities.resourceValues(forKeys: [.isPackageKey]).isPackage == false)
        #expect(Set(policy.discover().map(\.path)) == Set([userApp.path, systemApp.path]))
        #expect(policy.metadata(for: systemApp.path) != nil)
        let entries = CachedAppIndexBuilder(policy: policy, loadIcon: { _ in nil }).build(invalidation: .init())
        #expect(policy.metadata(for: systemApp.path) != nil)
        #expect(Set(entries.map(\.path)) == Set([userApp.path, systemApp.path]))
        let engine = LauncherEngine(config: config, entries: { entries }, apps: policy,
                                    openURL: { opened.append($0) })
        for query in ["useralias", "sysalias"] {
            let result = try #require(engine.search(query: query).first)
            engine.launch(result: result)
        }
        #expect(opened.map(\.path) == [userApp.path, systemApp.path])
        let backend = MockHotkeys()
        let hotkeys = ApplicationHotkeys(manager: HotkeyManager(backend: backend), apps: policy,
            openURL: { opened.append($0) }, toggle: {}, report: { Issue.record("Unexpected error: \($0)") })
        hotkeys.apply(config)
        #expect(backend.active.count == 3)
        for shortcut in ["Cmd+t", "Cmd+k"] {
            let binding = try HotkeyBinding.parse(shortcut)
            let id = try #require(backend.active.first { $0.value == binding }?.key)
            backend.onPress?(id)
        }
        #expect(opened.map(\.path) == [userApp.path, systemApp.path, userApp.path, systemApp.path])
        // Replacing a system app with an escaping link must never hand off.
        let outside = try app("Outside.app", under: fixture.url)
        try FileManager.default.removeItem(at: systemApp)
        try FileManager.default.createSymbolicLink(at: systemApp, withDestinationURL: outside)
        #expect(!policy.launch(path: systemApp.path, open: { opened.append($0) }))
        #expect(opened.count == 4)
        // Watcher construction is side-effect-free; never start an OS watcher.
        let watcher = FSEventsAppIndexWatcher(roots: policy.roots)
        #expect(watcher.roots == roots)
    }

    @Test func discoveryAndResolvedBoundaries() throws {
        let fixture = try TemporaryDirectory()
        let root = fixture.file("Applications")
        let ordinary = try app("Vendor/Good.app", under: root)
        let outer = try app("Outer.app", under: root)
        let helper = try app("Outer.app/Contents/Helpers/Helper.app", under: root)
        let external = try app("Outside.app", under: fixture.url)
        let prefixSibling = try app("Applications-other/Other.app", under: fixture.url)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("Escape.app"), withDestinationURL: external)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("Alias.app"), withDestinationURL: ordinary)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("HelperAlias.app"), withDestinationURL: helper)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("Loop"), withDestinationURL: root)
        let policy = AllowedApps(root: root)
        #expect(Set(policy.discover().map(\.path)) == Set([ordinary.path, outer.path]))
        #expect(policy.validatedURL(for: helper.path) == nil)
        #expect(policy.validatedURL(for: root.appendingPathComponent("HelperAlias.app").path) == nil)
        #expect(policy.validatedURL(for: root.appendingPathComponent("Escape.app").path) == nil)
        #expect(policy.validatedURL(for: prefixSibling.path) == nil)
        #expect(policy.validatedURL(for: external.path) == nil)
        #expect(policy.validatedURL(for: root.appendingPathComponent("Alias.app").path)?.path == ordinary.path)
        #expect(policy.validatedURL(for: root.appendingPathComponent("Missing.app").path) == nil)
    }

    @Test func metadataAndBrokenOutsideLinksAreRejected() throws {
        let fixture = try TemporaryDirectory()
        let root = fixture.file("Applications")
        let target = try app("Metadata.app", under: root)
        let outside = try app("Outside.app", under: fixture.url)
        let info = target.appendingPathComponent("Contents/Info.plist")
        try FileManager.default.removeItem(at: info)
        try FileManager.default.createSymbolicLink(at: info, withDestinationURL: outside.appendingPathComponent("Contents/Info.plist"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("Broken.app"), withDestinationURL: fixture.file("Missing.app"))
        let policy = AllowedApps(root: root)
        #expect(policy.validatedURL(for: target.path) == nil)
        #expect(policy.discover().isEmpty)
    }

    @Test func activationRevalidatesAndMocksHandoff() throws {
        let fixture = try TemporaryDirectory()
        let root = fixture.file("Applications")
        let target = try app("Good.app", under: root)
        let outside = try app("Outside.app", under: fixture.url)
        let policy = AllowedApps(root: root)
        var opened: [URL] = []
        #expect(policy.launch(path: target.path, open: { opened.append($0) }))
        #expect(opened.map(\.path) == [target.path])
        try FileManager.default.removeItem(at: target)
        try FileManager.default.createSymbolicLink(at: target, withDestinationURL: outside)
        #expect(!policy.launch(path: target.path, open: { opened.append($0) }))
        #expect(opened.map(\.path) == [target.path])
    }

    @Test func aliasesOnlyAcceptRealAllowedAppsOrWebURLs() throws {
        let fixture = try TemporaryDirectory()
        let root = fixture.file("Applications")
        let target = try app("Folder/Good.app", under: root)
        let helper = try app("Folder/Good.app/Contents/Helper.app", under: root)
        let url = fixture.file("config.toml")
        try """
        [aliases]
        app = "\(target.path)"
        helper = "\(helper.path)"
        arbitrary = "\(fixture.file("file.txt").path)"
        template = "\(root.path)/{query}.app"
        web = "https://example.invalid/{query}"
        """.write(to: url, atomically: true, encoding: .utf8)
        let config = ConfigManager(configURL: url, watchForChanges: false, apps: AllowedApps(root: root))
        #expect(config.aliases == ["app": target.path, "web": "https://example.invalid/{query}"])
    }
}
