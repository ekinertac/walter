// Borderless, fixed-position panel with local keyboard shortcuts.

import AppKit

class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }

    // AppKit treats Cmd-modified keys as menu key-equivalents and routes
    // them through performKeyEquivalent *before* the field editor's command
    // interpretation, so the text field's doCommandBy: never sees them — an
    // unhandled Cmd+Return just beeps. We intercept the launcher's Cmd
    // shortcuts here and forward to the controller.
    var onCommandReturn: (() -> Void)? // Reveal a revalidated allowed app only.
    var closeBinding: HotkeyBinding?
    var onClose: (() -> Void)?
    var onQuit: (() -> Void)?
    var onConfigLocation: (() -> Void)?
    var onQuickSelect: ((Int) -> Void)?       // Cmd+1…9 → launch Nth result
    var onCopyResult: (() -> Bool)?           // Cmd+C → copy result; returns true if handled

    override var isMovableByWindowBackground: Bool {
        get { false }
        set {}
    }
    override var isMovable: Bool {
        get { false }
        set {}
    }

    override func update() {
        InputTiming.shared.windowUpdate { super.update() }
    }

    override func sendEvent(_ event: NSEvent) {
        let timing = event.type == .keyDown ? InputTiming.shared.beginKeyEvent(timestamp: event.timestamp) : nil
        defer { InputTiming.shared.endKeyEvent(timing) }
        if handlePopupShortcut(event) { return }
        if event.type == .keyDown, closeBinding?.matches(event) == true {
            onClose?()
            return
        }
        super.sendEvent(event)
    }

    private func handlePopupShortcut(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return false }
        return PopupShortcuts.handle(characters: event.charactersIgnoringModifiers ?? "",
            modifiers: event.modifierFlags, popupActive: isVisible && isKeyWindow,
            quit: onQuit, showConfigLocation: onConfigLocation)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // AppKit can consult other windows for key equivalents while an alert
        // is key. Never route commands into the popup behind that alert.
        guard isVisible && isKeyWindow else { return super.performKeyEquivalent(with: event) }
        if handlePopupShortcut(event) { return true }
        // Only handle pure Command combos here; let everything else
        // (Cmd+Shift+…, Cmd+A/V/X text editing, etc.) flow to the responder
        // chain and the hidden Edit menu as before.
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags == .command else { return super.performKeyEquivalent(with: event) }

        if event.keyCode == 36 || event.keyCode == 76 {
            onCommandReturn?()
            return true
        }

        let chars = event.charactersIgnoringModifiers ?? ""

        // Cmd+1…9 → jump straight to and launch the Nth visible result.
        if let digit = Int(chars), (1...9).contains(digit) {
            onQuickSelect?(digit)
            return true
        }

        // Cmd+C → copy the selected result's value. But if the user has an
        // active text selection in the search field, defer to the normal
        // copy-text behavior so they can still copy what they typed.
        if chars == "c" {
            if let tv = firstResponder as? NSTextView, tv.selectedRange().length > 0 {
                return super.performKeyEquivalent(with: event)
            }
            if onCopyResult?() == true { return true }
        }

        return super.performKeyEquivalent(with: event)
    }
}
