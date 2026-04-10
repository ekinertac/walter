// HotkeyManager.swift — Global hotkey with event suppression
//
// Two layers work together:
//   1. CGEventTap — intercepts the key globally and SUPPRESSES it so the
//      active app never sees the Tab/Space/etc. character.
//   2. NSEvent local monitor — catches the key when Walter itself is frontmost
//      (CGEventTap doesn't fire for events going to the tap's own process).
//
// The CGEventTap runs on a dedicated background thread with its own CFRunLoop
// (same pattern that worked in our standalone test). The callback discards the
// matching keystroke and calls the action on the main thread.
//
// Requires Accessibility permission for CGEventTap.

import AppKit

class HotkeyManager {

    private var localMonitor: Any?
    private var tapThread: Thread?
    private let action: () -> Void
    private let targetKeyCode: UInt16
    private let targetModifiers: NSEvent.ModifierFlags

    // Shared state between the CGEventTap callback and the instance
    private static var sharedKeyCode: UInt16 = 49
    private static var sharedModifiers: NSEvent.ModifierFlags = .option
    private static var sharedAction: (() -> Void)?

    init(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, action: @escaping () -> Void) {
        self.action = action
        self.targetKeyCode = keyCode
        self.targetModifiers = modifiers

        // Store in statics so the C callback can access them
        Self.sharedKeyCode = keyCode
        Self.sharedModifiers = modifiers
        Self.sharedAction = action

        // CGEventTap on a background thread — suppresses the key globally
        startEventTap()

        // Local monitor for when Walter is frontmost
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if self?.matchesHotkey(event) == true {
                self?.action()
                return nil
            }
            return event
        }
    }

    deinit {
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
        }
        tapThread?.cancel()
    }

    // MARK: - Key binding parser

    static func parseBinding(_ binding: String) -> (UInt16, NSEvent.ModifierFlags) {
        let parts = binding.split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }

        var modifiers: NSEvent.ModifierFlags = []
        var keyCode: UInt16 = 49

        for part in parts {
            switch part {
            case "alt", "option", "opt":    modifiers.insert(.option)
            case "cmd", "command", "super": modifiers.insert(.command)
            case "ctrl", "control":         modifiers.insert(.control)
            case "shift":                   modifiers.insert(.shift)
            default:                        keyCode = keyNameToCode(part)
            }
        }

        return (keyCode, modifiers)
    }

    private static func keyNameToCode(_ name: String) -> UInt16 {
        switch name {
        case "space":           return 49
        case "tab":             return 48
        case "return", "enter": return 36
        case "escape", "esc":   return 53
        case "delete", "backspace": return 51
        case "a": return 0    case "b": return 11  case "c": return 8
        case "d": return 2    case "e": return 14  case "f": return 3
        case "g": return 5    case "h": return 4   case "i": return 34
        case "j": return 38   case "k": return 40  case "l": return 37
        case "m": return 46   case "n": return 45  case "o": return 31
        case "p": return 35   case "q": return 12  case "r": return 15
        case "s": return 1    case "t": return 17  case "u": return 32
        case "v": return 9    case "w": return 13  case "x": return 7
        case "y": return 16   case "z": return 6
        case "0": return 29  case "1": return 18  case "2": return 19
        case "3": return 20  case "4": return 21  case "5": return 23
        case "6": return 22  case "7": return 26  case "8": return 28
        case "9": return 25
        case "f1": return 122  case "f2": return 120  case "f3": return 99
        case "f4": return 118  case "f5": return 96   case "f6": return 97
        case "f7": return 98   case "f8": return 100  case "f9": return 101
        case "f10": return 109 case "f11": return 103 case "f12": return 111
        case "up": return 126  case "down": return 125
        case "left": return 123  case "right": return 124
        default:
            print("HotkeyManager: unknown key '\(name)', defaulting to Space")
            return 49
        }
    }

    // MARK: - CGEventTap (suppresses the key globally)

    private func startEventTap() {
        let thread = Thread {
            let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)

            guard let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,          // .defaultTap can modify/discard events
                eventsOfInterest: mask,
                callback: Self.eventTapCallback,
                userInfo: nil
            ) else {
                print("HotkeyManager: CGEventTap failed — Accessibility permission required")
                return
            }

            let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
            let runLoop = CFRunLoopGetCurrent()
            CFRunLoopAddSource(runLoop, source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            print("HotkeyManager: CGEventTap active (key events will be suppressed)")
            CFRunLoopRun()
        }
        thread.name = "walter-hotkey"
        thread.start()
        tapThread = thread
    }

    /// C-compatible callback. Returns nil to suppress the event, or the event to pass through.
    private static let eventTapCallback: CGEventTapCallBack = { _, type, event, _ in
        guard type == .keyDown else { return Unmanaged.passRetained(event) }

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags

        let relevant: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]
        var eventMods: NSEvent.ModifierFlags = []
        if flags.contains(.maskAlternate) { eventMods.insert(.option) }
        if flags.contains(.maskCommand) { eventMods.insert(.command) }
        if flags.contains(.maskControl) { eventMods.insert(.control) }
        if flags.contains(.maskShift) { eventMods.insert(.shift) }

        let relevantNS: NSEvent.ModifierFlags = [.command, .option, .control, .shift]

        if keyCode == sharedKeyCode && eventMods.intersection(relevantNS) == sharedModifiers {
            // Fire the action on main thread
            DispatchQueue.main.async { sharedAction?() }
            // Return nil to suppress the keystroke
            return nil
        }

        return Unmanaged.passRetained(event)
    }

    private func matchesHotkey(_ event: NSEvent) -> Bool {
        let relevant: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
        return event.keyCode == targetKeyCode
            && event.modifierFlags.intersection(relevant) == targetModifiers
    }
}
