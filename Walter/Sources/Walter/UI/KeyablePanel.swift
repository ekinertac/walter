// KeyablePanel.swift — NSPanel subclass that accepts keyboard input and dragging
//
// Borderless panels can't become key and can't be dragged by default.
// This subclass fixes both: typing works, and clicking anywhere on the
// panel background starts a window drag (like dragging a title bar).

import AppKit

class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }

    // Allow dragging the borderless panel by clicking anywhere on the background.
    // Text fields and other controls still receive clicks normally — this only
    // fires when the click lands on the panel's content view itself.
    override var isMovableByWindowBackground: Bool {
        get { true }
        set {}
    }
}
