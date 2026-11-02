import Foundation
import Testing
@testable import Walter

private final class MockHotkeys: HotkeyBackend {
    var onPress: ((UInt32) -> Void)?
    var active: [UInt32: HotkeyBinding] = [:]
    var fail: HotkeyBinding?
    var unregistered: [UInt32] = []
    func register(_ binding: HotkeyBinding, id: UInt32) throws {
        if fail == binding { throw HotkeyError.registration(-9878) }
        active[id] = binding
    }
    func unregister(id: UInt32) { active[id] = nil; unregistered.append(id) }
}

@Suite("Hotkey parsing and transactional registration (mock OS)")
struct HotkeyTests {
    @Test func normalizesAliasesAndOrder() throws {
        #expect(try HotkeyBinding.parse("Ctrl+Alt+Space") == HotkeyBinding.parse(" Option + Control + space "))
        #expect(try HotkeyBinding.parse("Cmd+Enter") == HotkeyBinding.parse("command+return"))
        #expect(try HotkeyBinding.parse("Cmd+Space") == HotkeyBinding.parse("Command + Space"))
    }
    @Test(arguments: ["", "Alt+", "Alt+Unknown", "Alt+Space+A", "Alt+Alt+Space", "Option", "Ctrl++A"])
    func invalidBindingRejected(text: String) {
        #expect(throws: (any Error).self) { try HotkeyBinding.parse(text) }
    }
    @Test func duplicatesAndLauncherConflictsRejected() throws {
        let backend = MockHotkeys()
        let manager = HotkeyManager(backend: backend)
        let binding = try HotkeyBinding.parse(ConfigManager.Keybindings().open)
        #expect(throws: (any Error).self) {
            try manager.replace(with: [.init(name: "launcher", binding: binding, action: {}),
                                       .init(name: "app", binding: binding, action: {})])
        }
        #expect(backend.active.isEmpty)
        #expect(throws: (any Error).self) {
            try manager.replace(with: [.init(name: "launcher", binding: try HotkeyBinding.parse("Space"), action: {})])
        }
    }
    @Test func reloadRollbackDispatchReuseAndCleanup() throws {
        let backend = MockHotkeys()
        var first = 0, second = 0
        let one = try HotkeyBinding.parse(ConfigManager.Keybindings().open)
        let two = try HotkeyBinding.parse("Ctrl+K")
        let three = try HotkeyBinding.parse("Ctrl+J")
        do {
            let manager = HotkeyManager(backend: backend)
            try manager.replace(with: [.init(name: "launcher", binding: one, action: { first += 1 })])
            let originalID = try #require(backend.active.first?.key)
            backend.onPress?(originalID)
            #expect(first == 1)
            backend.fail = three
            #expect(throws: (any Error).self) {
                try manager.replace(with: [.init(name: "launcher", binding: two, action: {}),
                    .init(name: "future-action", binding: three, action: {})])
            }
            #expect(backend.active == [originalID: one])
            backend.onPress?(originalID)
            #expect(first == 2)
            backend.fail = nil
            try manager.replace(with: [.init(name: "launcher", binding: one, action: { second += 1 }),
                .init(name: "future-action", binding: two, action: { second += 10 })])
            #expect(backend.active[originalID] == one)
            for id in backend.active.keys { backend.onPress?(id) }
            #expect(second == 11)
            backend.onPress?(UInt32.max)
            #expect(second == 11)
            try manager.replace(with: [.init(name: "launcher", binding: two, action: { second += 100 })])
            #expect(backend.active.count == 1)
            #expect(backend.unregistered.contains(originalID))
        }
        #expect(backend.active.isEmpty)
        #expect(backend.onPress == nil)
    }
}
