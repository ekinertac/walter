import Foundation
import Testing
@testable import Walter

// Synthetic local bundles, fake Carbon, recorded alerts/opens; no app lifecycle.
private final class AppHotkeyFixture {
    let directory: TemporaryDirectory
    let root: URL
    let config: ConfigManager
    let backend = MockHotkeys()
    var controller: ApplicationHotkeys!
    var opened: [URL] = []
    var errors: [String] = []
    var toggles = 0

    init() throws {
        directory = try TemporaryDirectory()
        root = directory.file("Applications")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        config = ConfigManager(configURL: directory.file("config.toml"), watchForChanges: false,
                               apps: AllowedApps(root: root))
        controller = ApplicationHotkeys(manager: HotkeyManager(backend: backend), apps: AllowedApps(root: root),
            openURL: { [weak self] in self?.opened.append($0) },
            toggle: { [weak self] in self?.toggles += 1 },
            report: { [weak self] in self?.errors.append(String(describing: $0)) })
    }

    func app(_ name: String, under parent: URL? = nil) throws -> URL {
        let url = (parent ?? root).appendingPathComponent(name)
        let contents = url.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(fromPropertyList: ["CFBundlePackageType": "APPL"], format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
        return url.standardizedFileURL
    }

    func apply(_ entries: String = "", launcher: String = "Ctrl+Space", close: String = "Escape") throws {
        try """
        [keybindings]
        open = "\(launcher)"
        close = "\(close)"
        [app_hotkeys]
        \(entries)
        """.write(to: config.configURL, atomically: true, encoding: .utf8)
        config.reload()
        controller.apply(config)
    }

    func press(_ text: String) throws {
        let binding = try HotkeyBinding.parse(text)
        let id = try #require(backend.active.first(where: { $0.value == binding })?.key)
        backend.onPress?(id)
    }
}

@Suite("Application hotkey config integration (mock OS)")
struct ApplicationHotkeysTests {
    @Test func launchReloadRemovalThemeReuseAndShutdown() throws {
        let f = try AppHotkeyFixture()
        let first = try f.app("First.app")
        let second = try f.app("Folder/Second.app")
        #expect(AllowedApps(root: f.root).validatedURL(for: first.path) != nil)
        try f.apply("\"Cmd+Ctrl+t\" = \"\(first.path)\"")
        #expect(f.errors.isEmpty, "\(f.errors)")
        #expect(f.backend.active.count == 2)
        let original = f.backend.active
        try f.press("Ctrl+Space")
        try f.press("Ctrl+Cmd+t")
        #expect(f.toggles == 1)
        #expect(f.opened == [first])
        f.config.selectTheme("dracula")
        f.config.reload()
        f.controller.apply(f.config)
        #expect(f.backend.active == original)
        #expect(f.backend.unregistered.isEmpty)
        try f.apply("\"Cmd+Ctrl+t\" = \"\(second.path)\"")
        #expect(f.backend.active == original) // Same binding, new action, no new handle.
        try f.press("Cmd+Ctrl+t")
        #expect(f.opened == [first, second])
        try f.apply()
        #expect(f.backend.active.count == 1)
        let removed = try #require(original.first(where: { $0.value == (try? HotkeyBinding.parse("Cmd+Ctrl+t")) })?.key)
        f.backend.onPress?(removed)
        #expect(f.opened == [first, second])
        #expect(f.errors.isEmpty)
        f.controller = nil
        #expect(f.backend.active.isEmpty)
        #expect(f.backend.onPress == nil)
    }

    @Test(arguments: ["Ctrl+Space", "Command+Control+t", "Cmd+Ctrl+t", "Cmd+Unknown", "t", "Cmd++t"])
    func invalidOrDuplicateBindingsKeepLauncher(binding: String) throws {
        let f = try AppHotkeyFixture()
        let app = try f.app("Good.app")
        try f.apply("\"Cmd+Ctrl+t\" = \"\(app.path)\"\n\"\(binding)\" = \"\(app.path)\"")
        #expect(f.backend.active.count == 1)
        #expect(!f.errors.isEmpty)
        try f.press("Ctrl+Space") // Use configured launcher, not default, on first-load app error.
        #expect(f.toggles == 1)
        #expect(f.opened.isEmpty)
    }

    @Test func registrationFailureRollsBackAndCanRetry() throws {
        let f = try AppHotkeyFixture()
        let first = try f.app("First.app")
        let second = try f.app("Second.app")
        try f.apply("\"Cmd+t\" = \"\(first.path)\"")
        let original = f.backend.active
        f.backend.fail = try HotkeyBinding.parse("Cmd+k")
        let entries = "\"Cmd+t\" = \"\(second.path)\"\n\"Cmd+k\" = \"\(second.path)\""
        try f.apply(entries, launcher: "Ctrl+j") // Stages a new launcher, then fails an app.
        #expect(f.backend.active == original)
        #expect(f.errors.last?.contains("Cmd+k") == true)
        #expect(f.errors.last?.contains("OSStatus") == true)
        try f.press("Ctrl+Space")
        try f.press("Cmd+t")
        #expect(f.opened == [first]) // Failed reload must also preserve old actions.
        f.backend.fail = nil
        try f.apply(entries, launcher: "Ctrl+j")
        #expect(f.backend.active.count == 3)
        try f.press("Ctrl+j")
        try f.press("Cmd+t")
        #expect(f.toggles == 2)
        #expect(f.opened == [first, second])
    }

    @Test func initialAppRegistrationFailureDoesNotDisableLauncher() throws {
        let f = try AppHotkeyFixture()
        let app = try f.app("Good.app")
        f.backend.fail = try HotkeyBinding.parse("Cmd+t")
        try f.apply("\"Cmd+t\" = \"\(app.path)\"")
        #expect(f.backend.active.count == 1)
        try f.press("Ctrl+Space")
        #expect(f.toggles == 1)
        #expect(!f.errors.isEmpty)
    }

    @MainActor @Test func filesystemReloadsHotkeysForInPlaceAndAtomicSaves() async throws {
        let f = try AppHotkeyFixture()
        let first = try f.app("First.app")
        let second = try f.app("Second.app")
        try f.apply("\"Cmd+t\" = \"\(first.path)\"")
        // Start real, test-scoped watchers only after the initial fixture is ready.
        let watched = ConfigManager(configURL: f.config.configURL, apps: AllowedApps(root: f.root))
        defer { watched.stopWatching() }
        var reloads = 0
        watched.onChange = { [weak watched] in
            guard let watched else { return }
            reloads += 1
            f.controller.apply(watched)
        }
        func save(_ binding: String?, path: String, atomically: Bool) throws {
            let entry = binding.map { "\"\($0)\" = \"\(path)\"" } ?? ""
            let content = "[keybindings]\nopen = \"Ctrl+Space\"\n[app_hotkeys]\n\(entry)\n"
            if atomically {
                try content.write(to: watched.configURL, atomically: true, encoding: .utf8)
            } else {
                // Guaranteed same-inode write, not an editor's rename/replacement.
                let handle = try FileHandle(forWritingTo: watched.configURL)
                defer { try? handle.close() }
                try handle.truncate(atOffset: 0)
                try handle.write(contentsOf: Data(content.utf8))
            }
        }
        func waitFor(_ binding: String?) async throws {
            let expected = try binding.map { try HotkeyBinding.parse($0) }
            for _ in 0..<60 {
                let appBindings = f.backend.active.values.filter { $0 != (try? HotkeyBinding.parse("Ctrl+Space")) }
                if Set(appBindings) == Set(expected.map { [$0] } ?? []) { return }
                try await Task.sleep(nanoseconds: 25_000_000)
            }
            let appBindings = f.backend.active.values.filter { $0 != (try? HotkeyBinding.parse("Ctrl+Space")) }
            try #require(Set(appBindings) == Set(expected.map { [$0] } ?? []),
                         "Filesystem save did not reload app hotkeys: \(binding ?? "removed")")
        }
        let oldID = try #require(f.backend.active.first { $0.value == (try? HotkeyBinding.parse("Cmd+t")) }?.key)
        try save("Cmd+k", path: second.path, atomically: false)
        try await waitFor("Cmd+k")
        f.backend.onPress?(oldID)
        #expect(f.opened.isEmpty)
        try f.press("Cmd+k")
        #expect(f.opened == [second])
        try save("Cmd+j", path: first.path, atomically: true)
        try await waitFor("Cmd+j")
        try f.press("Cmd+j")
        #expect(f.opened == [second, first])
        // The file watcher must follow the new inode after atomic replacement.
        try save("Cmd+l", path: second.path, atomically: false)
        try await waitFor("Cmd+l")
        try f.press("Cmd+l")
        #expect(f.opened == [second, first, second])
        try save("Cmd+g", path: "https://example.invalid", atomically: true)
        try await waitFor("Cmd+g")
        #expect(f.opened == [second, first, second]) // Reload is local only.
        try f.press("Cmd+g")
        #expect(f.opened.last?.absoluteString == "https://example.invalid")
        try save("Cmd+k", path: "http://changed.invalid/path#fragment", atomically: false)
        try await waitFor("Cmd+k")
        #expect(f.opened.count == 4)
        try f.press("Cmd+k")
        #expect(f.opened.last?.absoluteString == "http://changed.invalid/path#fragment")
        let removedURLID = try #require(f.backend.active.first { $0.value == (try? HotkeyBinding.parse("Cmd+k")) }?.key)
        try save(nil, path: first.path, atomically: true)
        try await waitFor(nil)
        f.backend.onPress?(removedURLID)
        #expect(f.opened.count == 5)
        #expect(f.errors.isEmpty)
        watched.stopWatching()
        let stoppedAt = reloads
        try save("Cmd+t", path: first.path, atomically: false)
        try await Task.sleep(nanoseconds: 300_000_000)
        #expect(reloads == stoppedAt)
        #expect(f.backend.active.count == 1)
    }

    @Test func totalRegistrationFailureShowsOneErrorAndCanRetry() throws {
        let f = try AppHotkeyFixture()
        f.backend.failAll = true
        try f.apply()
        #expect(f.backend.active.isEmpty)
        #expect(f.errors.count == 1)
        #expect(f.errors[0].contains("OSStatus"))
        f.backend.failAll = false
        try f.apply()
        try f.press("Ctrl+Space")
        #expect(f.toggles == 1)
    }

    @Test func launcherRegistrationConflictFallsBackAtStartup() throws {
        let f = try AppHotkeyFixture()
        f.backend.fail = try HotkeyBinding.parse("Ctrl+Space")
        try f.apply()
        #expect(f.backend.active.count == 1)
        try f.press("Cmd+Space")
        #expect(f.toggles == 1)
        #expect(f.errors.contains { $0.contains("OSStatus") })
        f.backend.fail = nil
        try f.apply()
        try f.press("Ctrl+Space")
        #expect(f.toggles == 2)
        #expect(f.backend.active.count == 1)
    }

    @Test func malformedReloadPreservesActionsUntilCorrected() throws {
        let f = try AppHotkeyFixture()
        let app = try f.app("Good.app")
        try f.apply("\"Cmd+t\" = \"\(app.path)\"")
        let original = f.backend.active
        try f.apply("Cmd+t = \"\(app.path)\"", launcher: "Ctrl+k")
        #expect(f.errors.last?.contains("Invalid [app_hotkeys] entry") == true)
        #expect(f.backend.active == original)
        try f.press("Cmd+t")
        #expect(f.opened == [app])
        try f.apply("\"Cmd+t\" = \"\(app.path)\"", launcher: "Ctrl+k")
        try f.press("Ctrl+k")
        #expect(f.toggles == 1)
    }

    @Test func invalidLauncherFallsBackAndFailedReloadPreservesWorkingSet() throws {
        let f = try AppHotkeyFixture()
        try f.apply(launcher: "Cmd+Unknown")
        try f.press("Cmd+Space")
        let original = f.backend.active
        try f.apply(launcher: "Ctrl+k", close: "Unknown")
        #expect(f.backend.active == original)
        try f.press("Cmd+Space")
        #expect(f.toggles == 2)
        #expect(f.errors.count >= 2)
    }

    @Test func urlsAndAppsShareHotkeysWithoutOpeningOnReload() throws {
        let f = try AppHotkeyFixture()
        let app = try f.app("Good.app")
        let target = "https://example.invalid/?a=1&b=2#fragment"
        try f.apply("\"Cmd+t\" = \"\(app.path)\"\n\"Cmd+g\" = \"\(target)\"")
        #expect(f.errors.isEmpty)
        #expect(f.backend.active.count == 3)
        #expect(f.opened.isEmpty)
        #expect(f.toggles == 0)
        try f.press("Cmd+t")
        try f.press("Cmd+g")
        #expect(f.opened.map(\.absoluteString) == [app.absoluteString, target])
        #expect(f.toggles == 0) // Neither action reveals/toggles the popup.
        let original = f.backend.active
        f.config.selectTheme("dracula")
        f.config.reload()
        f.controller.apply(f.config)
        #expect(f.backend.active == original)
        #expect(f.opened.count == 2)
        // A reused binding can change from URL to app or app to URL.
        try f.apply("\"Cmd+t\" = \"http://other.invalid\"\n\"Cmd+g\" = \"\(app.path)\"")
        #expect(f.backend.active == original)
        #expect(f.opened.count == 2)
        try f.press("Cmd+t")
        try f.press("Cmd+g")
        #expect(f.opened.map(\.absoluteString) == [app.absoluteString, target, "http://other.invalid", app.absoluteString])
        let removed = try #require(original.first { $0.value == (try? HotkeyBinding.parse("Cmd+t")) }?.key)
        try f.apply()
        f.backend.onPress?(removed)
        #expect(f.opened.count == 4)
        #expect(f.backend.active.count == 1)
        #expect(f.errors.isEmpty)
    }

    @Test(arguments: ["file:///private/tmp/file", "javascript:alert(1)", "mailto:me@example.invalid",
                      "ftp://example.invalid", "https://", "https://example.invalid/{query}",
                      "!https://example.invalid"])
    func invalidURLsPreserveWorkingActions(target: String) throws {
        let f = try AppHotkeyFixture()
        try f.apply("\"Cmd+g\" = \"https://original.invalid\"")
        let original = f.backend.active
        try f.apply("\"Cmd+g\" = \"\(target)\"")
        #expect(f.backend.active == original)
        #expect(f.errors.count == 1)
        #expect(f.errors[0].contains(target))
        #expect(f.opened.isEmpty)
        try f.press("Cmd+g")
        #expect(f.opened.map(\.absoluteString) == ["https://original.invalid"])
    }

    @Test func urlRegistrationFailurePreservesOldDestination() throws {
        let f = try AppHotkeyFixture()
        try f.apply("\"Cmd+g\" = \"https://original.invalid\"")
        let original = f.backend.active
        f.backend.fail = try HotkeyBinding.parse("Cmd+k")
        let entries = "\"Cmd+g\" = \"https://replacement.invalid\"\n\"Cmd+k\" = \"https://new.invalid\""
        try f.apply(entries)
        #expect(f.backend.active == original)
        #expect(f.errors.count == 1)
        #expect(f.opened.isEmpty)
        try f.press("Cmd+g")
        #expect(f.opened.map(\.absoluteString) == ["https://original.invalid"])
        f.backend.fail = nil
        try f.apply(entries)
        try f.press("Cmd+g")
        try f.press("Cmd+k")
        #expect(f.opened.map(\.absoluteString) == ["https://original.invalid", "https://replacement.invalid", "https://new.invalid"])
    }

    @Test func missingDisallowedAndEscapingPathsAreRejected() throws {
        let f = try AppHotkeyFixture()
        let outside = try f.app("Outside.app", under: f.directory.url)
        _ = try f.app("Outer.app")
        let helper = try f.app("Outer.app/Contents/Helper.app")
        let file = f.root.appendingPathComponent("File.app")
        try Data().write(to: file)
        let link = f.root.appendingPathComponent("Escape.app")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        for path in [outside.path, helper.path, file.path, link.path,
                     f.root.appendingPathComponent("Missing.app").path, "!echo ignored"] {
            try f.apply("\"Cmd+t\" = \"\(path)\"")
            #expect(f.backend.active.count == 1)
            #expect(f.errors.last?.contains(path) == true)
        }
        #expect(f.opened.isEmpty)
    }

    @Test func activationRevalidatesOriginalSymlinkPathAndReportsMissingApp() throws {
        let f = try AppHotkeyFixture()
        let app = try f.app("Good.app")
        let outside = try f.app("Outside.app", under: f.directory.url)
        let link = f.root.appendingPathComponent("Alias.app")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: app)
        try f.apply("\"Cmd+t\" = \"\(link.path)\"")
        try f.press("Cmd+t")
        #expect(f.opened == [app])
        try FileManager.default.removeItem(at: link)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        try f.press("Cmd+t")
        #expect(f.opened == [app])
        #expect(f.errors.last?.contains(link.path) == true)
        try f.apply("\"Cmd+t\" = \"\(app.path)\"")
        try FileManager.default.removeItem(at: app)
        try f.press("Cmd+t")
        #expect(f.opened == [app])
        #expect(f.errors.last?.contains(app.path) == true)
    }
}
