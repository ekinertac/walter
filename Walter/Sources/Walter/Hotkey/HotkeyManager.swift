// Carbon hotkeys: no event taps, monitoring permissions, or polling threads.
import AppKit
import Carbon.HIToolbox

struct HotkeyBinding: Hashable {
    let keyCode: UInt32
    let modifiers: UInt32

    static func parse(_ text: String) throws -> HotkeyBinding {
        let parts = text.lowercased().split(separator: "+", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        var modifiers: UInt32 = 0
        var key: UInt32?
        for part in parts {
            let flag: UInt32?
            switch part {
            case "alt", "option", "opt": flag = UInt32(optionKey)
            case "cmd", "command", "super": flag = UInt32(cmdKey)
            case "ctrl", "control": flag = UInt32(controlKey)
            case "shift": flag = UInt32(shiftKey)
            default: flag = nil
            }
            if let flag {
                guard modifiers & flag == 0 else { throw HotkeyError.invalid(text) }
                modifiers |= flag
            } else {
                guard key == nil, let code = keys[part] else { throw HotkeyError.invalid(text) }
                key = code
            }
        }
        guard let key else { throw HotkeyError.invalid(text) }
        return HotkeyBinding(keyCode: key, modifiers: modifiers)
    }

    func matches(_ event: NSEvent) -> Bool {
        var flags: UInt32 = 0
        if event.modifierFlags.contains(.command) { flags |= UInt32(cmdKey) }
        if event.modifierFlags.contains(.option) { flags |= UInt32(optionKey) }
        if event.modifierFlags.contains(.control) { flags |= UInt32(controlKey) }
        if event.modifierFlags.contains(.shift) { flags |= UInt32(shiftKey) }
        return UInt32(event.keyCode) == keyCode && flags == modifiers
    }

    private static let keys: [String: UInt32] = [
        "space": 49, "tab": 48, "return": 36, "enter": 36, "escape": 53, "esc": 53,
        "delete": 51, "backspace": 51,
        "a": 0, "b": 11, "c": 8, "d": 2, "e": 14, "f": 3, "g": 5, "h": 4,
        "i": 34, "j": 38, "k": 40, "l": 37, "m": 46, "n": 45, "o": 31,
        "p": 35, "q": 12, "r": 15, "s": 1, "t": 17, "u": 32, "v": 9, "w": 13,
        "x": 7, "y": 16, "z": 6,
        "0": 29, "1": 18, "2": 19, "3": 20, "4": 21, "5": 23, "6": 22, "7": 26, "8": 28, "9": 25,
        "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97,
        "f7": 98, "f8": 100, "f9": 101, "f10": 109, "f11": 103, "f12": 111,
        "up": 126, "down": 125, "left": 123, "right": 124
    ]
}

enum HotkeyError: Error, CustomStringConvertible {
    case invalid(String), duplicate, registration(Int32)
    var description: String {
        switch self {
        case .invalid(let text): return "Invalid hotkey: \(text). Use a known key and modifiers, e.g. Cmd+Space."
        case .duplicate: return "Hotkeys have duplicate names or normalized bindings (including the launcher)."
        case .registration(let status): return "macOS could not register the hotkey (OSStatus \(status)). It may be in use by another app or a system shortcut."
        }
    }
}

protocol HotkeyBackend: AnyObject {
    var onPress: ((UInt32) -> Void)? { get set }
    func register(_ binding: HotkeyBinding, id: UInt32) throws
    func unregister(id: UInt32)
}

/// Owns all registrations independently of the panel/tray. A reload stages new
/// handles before releasing old ones; any failure rolls back without losing a
/// working launcher. Reused bindings retain handles but can receive new actions.
final class HotkeyManager {
    struct Request {
        let name: String
        let binding: HotkeyBinding
        let action: () -> Void
    }
    private let backend: HotkeyBackend
    private var registrations: [HotkeyBinding: UInt32] = [:]
    private var actions: [UInt32: () -> Void] = [:]
    private var nextID: UInt32 = 1

    init(backend: HotkeyBackend) {
        self.backend = backend
        backend.onPress = { [weak self] id in self?.actions[id]?() }
    }

    deinit {
        backend.onPress = nil
        for id in registrations.values { backend.unregister(id: id) }
    }

    func replace(with requests: [Request]) throws {
        guard Set(requests.map { $0.name }).count == requests.count,
              Set(requests.map { $0.binding }).count == requests.count else { throw HotkeyError.duplicate }
        var staged: [HotkeyBinding: UInt32] = [:]
        var newIDs: [UInt32] = []
        var newActions: [UInt32: () -> Void] = [:]
        do {
            for request in requests {
                guard request.binding.modifiers != 0 else { throw HotkeyError.invalid(request.name) }
                let id: UInt32
                if let existing = registrations[request.binding] { id = existing }
                else {
                    guard nextID < UInt32.max else { throw HotkeyError.registration(-1) }
                    id = nextID; nextID += 1
                    try backend.register(request.binding, id: id)
                    newIDs.append(id)
                }
                staged[request.binding] = id
                newActions[id] = request.action
            }
        } catch {
            for id in newIDs { backend.unregister(id: id) }
            throw error
        }
        for (binding, id) in registrations where staged[binding] == nil { backend.unregister(id: id) }
        registrations = staged
        actions = newActions
    }
}

/// Only production code constructs this backend. Tests use an in-memory mock.
final class CarbonHotkeyBackend: HotkeyBackend {
    var onPress: ((UInt32) -> Void)?
    private var handles: [UInt32: EventHotKeyRef] = [:]
    private var handler: EventHandlerRef?
    private static let signature: OSType = 0x57414C54 // WALT

    init() throws {
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var hotkey = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hotkey)
            guard status == noErr, hotkey.signature == CarbonHotkeyBackend.signature else { return OSStatus(eventNotHandledErr) }
            Unmanaged<CarbonHotkeyBackend>.fromOpaque(context).takeUnretainedValue().onPress?(hotkey.id)
            return noErr
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard status == noErr else { throw HotkeyError.registration(status) }
    }

    func register(_ binding: HotkeyBinding, id: UInt32) throws {
        var handle: EventHotKeyRef?
        let status = RegisterEventHotKey(binding.keyCode, binding.modifiers,
            EventHotKeyID(signature: Self.signature, id: id), GetApplicationEventTarget(), 0, &handle)
        guard status == noErr, let handle else { throw HotkeyError.registration(status) }
        handles[id] = handle
    }

    func unregister(id: UInt32) {
        if let handle = handles.removeValue(forKey: id) { UnregisterEventHotKey(handle) }
    }

    deinit {
        for handle in handles.values { UnregisterEventHotKey(handle) }
        if let handler { RemoveEventHandler(handler) }
    }
}
