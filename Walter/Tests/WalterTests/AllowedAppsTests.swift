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
