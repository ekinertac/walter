import Foundation
import Testing
@testable import Walter

@Suite("Finder-only hotkey exception (synthetic bundles and mock OS)")
struct FinderHotkeyTests {
    // Finder's actual Info.plist uses FNDR, unlike ordinary APPL bundles.
    private func finder(under parent: URL, identifier: String = "com.apple.finder", type: String = "FNDR") throws -> URL {
        let url = parent.appendingPathComponent("CoreServices/Finder.app", isDirectory: true)
        let contents = url.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(fromPropertyList:
            ["CFBundlePackageType": type, "CFBundleIdentifier": identifier], format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
        return url
    }

    @Test func exactPathOnlyAndOrdinaryPolicyUnchanged() throws {
        #expect(FinderHotkeyTarget.path == "/System/Library/CoreServices/Finder.app")
        let fixture = try TemporaryDirectory()
        let url = try finder(under: fixture.url)
        let target = FinderHotkeyTarget(url: url)
        #expect(target.validatedURL(for: url.path) == url)
        for path in [url.path + "/", url.path + "/Contents/Helper.app",
                     url.path.replacingOccurrences(of: "Finder.app", with: "Other.app"),
                     url.path.replacingOccurrences(of: "Finder.app", with: "./Finder.app"),
                     url.absoluteString, "Finder.app"] {
            #expect(target.validatedURL(for: path) == nil)
        }
        let ordinary = AllowedApps(roots: [])
        #expect(ordinary.validatedURL(for: url.path) == nil)
        #expect(ordinary.discover().isEmpty)
        let configURL = fixture.file("config.toml")
        try "[aliases]\nfinder = \"\(url.path)\"\n".write(to: configURL, atomically: true, encoding: .utf8)
        let config = ConfigManager(configURL: configURL, watchForChanges: false, apps: ordinary)
        #expect(config.aliases.isEmpty)
    }

    @Test(arguments: ["CoreServices", "CoreServices/Finder.app", "CoreServices/Finder.app/Contents", "CoreServices/Finder.app/Contents/Info.plist"])
    func redirectedComponentsAreRejected(component: String) throws {
        let fixture = try TemporaryDirectory()
        let original = fixture.file("original")
        let redirected = fixture.file("redirected")
        let url = try finder(under: original)
        _ = try finder(under: redirected)
        let componentURL = original.appendingPathComponent(component)
        try FileManager.default.removeItem(at: componentURL)
        try FileManager.default.createSymbolicLink(at: componentURL,
            withDestinationURL: redirected.appendingPathComponent(component))
        #expect(FinderHotkeyTarget(url: url).validatedURL(for: url.path) == nil)
    }

    @Test(arguments: [("other.bundle", "FNDR"), ("com.apple.finder", "APPL"), ("com.apple.finder", "BNDL")])
    func invalidMetadataRejected(identifier: String, type: String) throws {
        let fixture = try TemporaryDirectory()
        let url = try finder(under: fixture.url, identifier: identifier, type: type)
        #expect(FinderHotkeyTarget(url: url).validatedURL(for: url.path) == nil)
    }

    @Test func missingBundleMetadataAndPlainFileRejected() throws {
        let fixture = try TemporaryDirectory()
        let url = try finder(under: fixture.url)
        let target = FinderHotkeyTarget(url: url)
        try FileManager.default.removeItem(at: url.appendingPathComponent("Contents/Info.plist"))
        #expect(target.validatedURL(for: url.path) == nil)
        try FileManager.default.removeItem(at: url)
        #expect(target.validatedURL(for: url.path) == nil)
        try Data().write(to: url)
        #expect(target.validatedURL(for: url.path) == nil)
    }

    @Test func hotkeyDispatchReloadRemovalAndActivationRevalidation() throws {
        let fixture = try TemporaryDirectory()
        let url = try finder(under: fixture.url)
        let configURL = fixture.file("config.toml")
        func save(_ entry: String) throws {
            try "[keybindings]\nopen = \"Ctrl+Space\"\n[app_hotkeys]\n\(entry)\n".write(
                to: configURL, atomically: true, encoding: .utf8)
        }
        let entry = "\"Cmd+Ctrl+f\" = \"\(url.path)\""
        try save(entry)
        let config = ConfigManager(configURL: configURL, watchForChanges: false, apps: AllowedApps(roots: []))
        let backend = MockHotkeys()
        var opened: [URL] = []
        var errors: [String] = []
        let hotkeys = ApplicationHotkeys(manager: HotkeyManager(backend: backend), apps: AllowedApps(roots: []),
            finder: FinderHotkeyTarget(url: url), openURL: { opened.append($0) }, toggle: {},
            report: { errors.append(String(describing: $0)) })
        hotkeys.apply(config)
        let binding = try HotkeyBinding.parse("Cmd+Ctrl+f")
        let id = try #require(backend.active.first { $0.value == binding }?.key)
        backend.onPress?(id)
        #expect(opened == [url])
        #expect(errors.isEmpty)
        try save("")
        config.reload()
        hotkeys.apply(config)
        #expect(backend.active.count == 1)
        backend.onPress?(id)
        #expect(opened == [url])
        try save(entry)
        config.reload()
        hotkeys.apply(config)
        let newID = try #require(backend.active.first { $0.value == binding }?.key)
        #expect(newID != id)
        let redirected = try finder(under: fixture.file("redirected"))
        let info = url.appendingPathComponent("Contents/Info.plist")
        try FileManager.default.removeItem(at: info)
        try FileManager.default.createSymbolicLink(at: info, withDestinationURL: redirected.appendingPathComponent("Contents/Info.plist"))
        backend.onPress?(newID)
        #expect(opened == [url]) // No handoff after the target's metadata changes.
        #expect(errors.count == 1)
        #expect(errors[0].contains(url.path))
        hotkeys.apply(config) // Unchanged config still revalidates at activation.
        backend.onPress?(newID)
        #expect(opened == [url])
        #expect(errors.count == 2)
    }
}
