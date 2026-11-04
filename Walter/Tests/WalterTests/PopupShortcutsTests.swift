import AppKit
import Testing
@testable import Walter

@Suite("Iconless popup commands (mock actions and alerts, no GUI)")
struct PopupShortcutsTests {
    @Test func localCommandsInvokeOnlyTheirOwnCallback() {
        var quits = 0, notices = 0
        #expect(PopupShortcuts.handle(characters: "q", modifiers: .command,
            popupActive: true, quit: { quits += 1 }, showConfigLocation: { notices += 1 }))
        #expect(quits == 1 && notices == 0)
        #expect(PopupShortcuts.handle(characters: ",", modifiers: .command,
            popupActive: true, quit: { quits += 1 }, showConfigLocation: { notices += 1 }))
        #expect(quits == 1 && notices == 1)
        #expect(PopupShortcuts.handle(characters: "Q", modifiers: [.command, .capsLock],
            popupActive: true, quit: { quits += 1 }, showConfigLocation: { notices += 1 }))
        #expect(quits == 2 && notices == 1)
    }

    @Test(arguments: ["a", "c", "v", "x", "z", "1", "\r", "", "qq"])
    func unrelatedShortcutsPassThrough(characters: String) {
        #expect(!PopupShortcuts.handle(characters: characters, modifiers: .command,
            popupActive: true, quit: { Issue.record("Unexpected quit") },
            showConfigLocation: { Issue.record("Unexpected alert") }))
    }

    @Test func inactivePopupCannotConsumeOrPerformCommands() {
        for characters in ["q", ","] {
            #expect(!PopupShortcuts.handle(characters: characters, modifiers: .command,
                popupActive: false, quit: { Issue.record("Unexpected quit") },
                showConfigLocation: { Issue.record("Unexpected alert") }))
        }
    }

    @Test func additionalModifiersAndPlainTypingPassThrough() {
        let modifiers: [NSEvent.ModifierFlags] = [[], .shift, .option, .control,
            [.command, .shift], [.command, .option], [.command, .control]]
        for flags in modifiers {
            for characters in ["q", ","] {
                #expect(!PopupShortcuts.handle(characters: characters, modifiers: flags,
                    popupActive: true, quit: { Issue.record("Unexpected quit") },
                    showConfigLocation: { Issue.record("Unexpected alert") }))
            }
        }
    }

    @Test func missingHandlersDoNotSwallowKeys() {
        for characters in ["q", ","] {
            #expect(!PopupShortcuts.handle(characters: characters, modifiers: .command,
                popupActive: true, quit: nil, showConfigLocation: nil))
        }
    }

    @Test func noticeUsesActualConfigURLAndExplainsReload() throws {
        let fixture = try TemporaryDirectory()
        let url = fixture.file("alternate config/config.toml")
        let config = ConfigManager(configURL: url, watchForChanges: false)
        let notice = ConfigLocationNotice(configURL: config.configURL)
        #expect(notice.path == url.path)
        #expect(notice.message.contains(url.path))
        #expect(notice.message.contains("Saved changes reload automatically"))
    }

    @Test func dismissalRestoresTheCurrentPanelAfterPresentation() {
        let presenter = ConfigLocationPresenter()
        var currentPanel = "original"
        var events: [String] = []
        let url = URL(fileURLWithPath: "/unused/config.toml")
        presenter.show(configURL: url, present: { _ in
            events.append("present")
            currentPanel = "replacement" // Model a config-driven panel rebuild.
            events.append("dismiss")
        }, restoreFocus: { events.append("focus-\(currentPanel)") })
        #expect(events == ["present", "dismiss", "focus-replacement"])
        presenter.show(configURL: url, present: { _ in events.append("second") },
            restoreFocus: { events.append("focus-again") })
        #expect(Array(events.suffix(2)) == ["second", "focus-again"])
    }

    @Test func nestedPresentationDoesNotOpenAnotherAlertOrRestoreEarly() {
        let presenter = ConfigLocationPresenter()
        let url = URL(fileURLWithPath: "/unused/config.toml")
        var events: [String] = []
        presenter.show(configURL: url, present: { _ in
            events.append("present")
            presenter.show(configURL: url,
                present: { _ in Issue.record("Unexpected nested alert") },
                restoreFocus: { Issue.record("Unexpected early focus restoration") })
            events.append("dismiss")
        }, restoreFocus: { events.append("focus") })
        #expect(events == ["present", "dismiss", "focus"])
    }

    @Test func focusRestorationDoesNotRevealHiddenPopupOrStealActivation() {
        for visible in [false, true] {
            for active in [false, true] {
                #expect(ConfigLocationPresenter.shouldRestoreFocus(popupVisible: visible,
                    applicationActive: active) == (visible && active))
            }
        }
    }
}
