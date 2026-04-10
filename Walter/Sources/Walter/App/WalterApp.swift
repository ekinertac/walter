// WalterApp.swift — Application entry point
//
// Walter runs as a menu bar agent (LSUIElement = true): no Dock icon, no
// main menu bar. The lifecycle is:
//   1. NSApp launches as an accessory (agent) app
//   2. StatusBarController creates the menu bar icon
//   3. HotkeyManager registers Alt+Space via NSEvent.addGlobalMonitorForEvents
//   4. The launcher panel is shown immediately on first launch
//   5. ESC hides the panel; Alt+Space toggles it; tray Quit exits
//
// AppKit is used instead of SwiftUI because:
//   - NSPanel with .nonactivatingPanel gives proper floating-above-all behaviour
//   - We need precise control over activation policy and key event handling
//   - SwiftUI's window management is too opinionated for a launcher

import AppKit

@main
struct WalterApp {
    static func main() {
        let app = NSApplication.shared

        // Agent app: no Dock icon, no main menu bar.
        app.setActivationPolicy(.accessory)

        let delegate = AppDelegate()
        app.delegate = delegate

        app.run()
    }
}
