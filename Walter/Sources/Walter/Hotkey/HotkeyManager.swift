// HotkeyManager.swift — Global hotkey via NSEvent monitor
//
// Uses NSEvent.addGlobalMonitorForEvents (for when Walter is NOT the active
// app) and NSEvent.addLocalMonitorForEvents (for when it IS active).
// Both are needed: global catches keystrokes from other apps, local catches
// them when the panel is focused.
//
// Requires Accessibility permission for the global monitor. If not granted,
// the local monitor still works (so the hotkey works when the panel is visible)
// and we log instructions for enabling Accessibility.
//
// This is the exact same API that Alfred and Raycast use. It just works.

import AppKit
import Carbon.HIToolbox

class HotkeyManager {

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private let action: () -> Void
    private let targetKeyCode: UInt16
    private let targetModifiers: NSEvent.ModifierFlags

    /// Creates monitors for the given key + modifier combo.
    /// `keyCode`: virtual key code (49 = Space, see Events.h)
    /// `modifiers`: e.g. .option for Alt, .command for Cmd
    init(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, action: @escaping () -> Void) {
        self.action = action
        self.targetKeyCode = keyCode
        self.targetModifiers = modifiers

        // Global monitor — fires when another app is frontmost.
        // Requires Accessibility permission; returns nil if not granted.
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleEvent(event)
        }

        if globalMonitor == nil {
            print("""
            ⚠️  Accessibility permission not granted — global hotkey won't work.
               System Settings → Privacy & Security → Accessibility
               Add Walter, then restart.
            """)
        }

        // Local monitor — fires when Walter itself is frontmost.
        // Does NOT require Accessibility.
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if self?.matchesHotkey(event) == true {
                self?.action()
                return nil // consume the event
            }
            return event // pass through
        }
    }

    deinit {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    private func handleEvent(_ event: NSEvent) {
        if matchesHotkey(event) {
            action()
        }
    }

    private func matchesHotkey(_ event: NSEvent) -> Bool {
        // Check key code matches and that exactly our modifier is held
        // (mask out irrelevant bits like caps lock, function key, etc.)
        let relevant: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
        return event.keyCode == targetKeyCode
            && event.modifierFlags.intersection(relevant) == targetModifiers
    }
}
