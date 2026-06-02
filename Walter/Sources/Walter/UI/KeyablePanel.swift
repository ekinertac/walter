// KeyablePanel.swift — NSPanel subclass that accepts keyboard input and dragging
//
// Borderless panels can't become key and can't be dragged by default.
// This subclass fixes both: typing works, and clicking anywhere on the
// panel background starts a window drag (like dragging a title bar).

import AppKit

class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }

    // AppKit treats Cmd-modified keys as menu key-equivalents and routes
    // them through performKeyEquivalent *before* the field editor's command
    // interpretation, so the text field's doCommandBy: never sees them — an
    // unhandled Cmd+Return just beeps. We intercept the launcher's Cmd
    // shortcuts here and forward to the controller.
    var onCommandReturn: (() -> Void)?        // Cmd+Return → reveal in Finder
    var onQuickSelect: ((Int) -> Void)?       // Cmd+1…9 → launch Nth result
    var onCopyResult: (() -> Bool)?           // Cmd+C → copy result; returns true if handled

    // Allow dragging the borderless panel by clicking anywhere on the background.
    // Text fields and other controls still receive clicks normally — this only
    // fires when the click lands on the panel's content view itself.
    override var isMovableByWindowBackground: Bool {
        get { true }
        set {}
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Only handle pure Command combos here; let everything else
        // (Cmd+Shift+…, Cmd+A/V/X text editing, etc.) flow to the responder
        // chain and the hidden Edit menu as before.
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags == .command else { return super.performKeyEquivalent(with: event) }

        // Cmd+Return / keypad-Enter → reveal in Finder.
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
