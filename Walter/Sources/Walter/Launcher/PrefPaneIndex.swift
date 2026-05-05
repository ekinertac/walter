// PrefPaneIndex.swift — System Settings pane search source
//
// macOS 13+ (Ventura) replaced System Preferences.app with System Settings.app.
// The legacy /System/Library/PreferencePanes/*.prefPane bundles are empty
// stubs on modern macOS — they cannot be read via Bundle/Info.plist anymore.
//
// Instead, System Settings exposes each pane via the URL scheme
//   x-apple.systempreferences:<bundle-identifier>
// and NSWorkspace.shared.open() launches Settings to the right pane.
//
// This file hardcodes the list of common panes (name, SF Symbol, URL).
// Searched by fuzzy match. Surfaced by LauncherEngine between the system
// commands group and the apps group.
//
// Called by: LauncherEngine.search() on every keystroke.
// Related: SystemCommands.swift (similar built-in actions),
//          LauncherEngine.swift (search pipeline + .url action handler).

import AppKit

struct PrefPane {
    let name: String        // display name (e.g. "Bluetooth")
    let iconName: String    // SF Symbol
    let url: String         // x-apple.systempreferences:... URL
}

class PrefPaneIndex {

    /// Hardcoded list of System Settings panes. URLs verified on macOS 13–15.
    /// Order is alphabetical for predictable empty-query browsing.
    private let panes: [PrefPane] = [
        PrefPane(name: "Accessibility", iconName: "figure.roll",
                 url: "x-apple.systempreferences:com.apple.preference.universalaccess"),
        PrefPane(name: "Appearance", iconName: "paintbrush",
                 url: "x-apple.systempreferences:com.apple.Appearance-Settings.extension"),
        PrefPane(name: "Apple ID", iconName: "person.crop.circle",
                 url: "x-apple.systempreferences:com.apple.systempreferences.AppleIDSettings"),
        PrefPane(name: "Battery", iconName: "battery.100",
                 url: "x-apple.systempreferences:com.apple.Battery-Settings.extension"),
        PrefPane(name: "Bluetooth", iconName: "bolt.horizontal",
                 url: "x-apple.systempreferences:com.apple.BluetoothSettings"),
        PrefPane(name: "Control Center", iconName: "switch.2",
                 url: "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension"),
        PrefPane(name: "Date & Time", iconName: "clock",
                 url: "x-apple.systempreferences:com.apple.Date-Time-Settings.extension"),
        PrefPane(name: "Desktop & Dock", iconName: "menubar.dock.rectangle",
                 url: "x-apple.systempreferences:com.apple.Desktop-Settings.extension"),
        PrefPane(name: "Displays", iconName: "display",
                 url: "x-apple.systempreferences:com.apple.Displays-Settings.extension"),
        PrefPane(name: "Energy Saver", iconName: "leaf",
                 url: "x-apple.systempreferences:com.apple.Energy-Saver-Settings.extension"),
        PrefPane(name: "Focus", iconName: "moon.circle",
                 url: "x-apple.systempreferences:com.apple.Focus-Settings.extension"),
        PrefPane(name: "Game Center", iconName: "gamecontroller",
                 url: "x-apple.systempreferences:com.apple.Game-Center-Settings.extension"),
        PrefPane(name: "General", iconName: "gear",
                 url: "x-apple.systempreferences:com.apple.preference.general"),
        PrefPane(name: "iCloud", iconName: "cloud",
                 url: "x-apple.systempreferences:com.apple.systempreferences.AppleIDSettings"),
        PrefPane(name: "Internet Accounts", iconName: "at",
                 url: "x-apple.systempreferences:com.apple.Internet-Accounts-Settings.extension"),
        PrefPane(name: "Keyboard", iconName: "keyboard",
                 url: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension"),
        PrefPane(name: "Lock Screen", iconName: "lock.display",
                 url: "x-apple.systempreferences:com.apple.Lock-Screen-Settings.extension"),
        PrefPane(name: "Login Items", iconName: "arrow.up.right.square",
                 url: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"),
        PrefPane(name: "Mouse", iconName: "magicmouse",
                 url: "x-apple.systempreferences:com.apple.Mouse-Settings.extension"),
        PrefPane(name: "Network", iconName: "network",
                 url: "x-apple.systempreferences:com.apple.Network-Settings.extension"),
        PrefPane(name: "Notifications", iconName: "bell.badge",
                 url: "x-apple.systempreferences:com.apple.Notifications-Settings.extension"),
        PrefPane(name: "Passwords", iconName: "key",
                 url: "x-apple.systempreferences:com.apple.Passwords-Settings.extension"),
        PrefPane(name: "Printers & Scanners", iconName: "printer",
                 url: "x-apple.systempreferences:com.apple.Print-Scan-Settings.extension"),
        PrefPane(name: "Privacy & Security", iconName: "hand.raised",
                 url: "x-apple.systempreferences:com.apple.preference.security"),
        PrefPane(name: "Screen Saver", iconName: "moon.stars",
                 url: "x-apple.systempreferences:com.apple.ScreenSaver-Settings.extension"),
        PrefPane(name: "Screen Time", iconName: "hourglass",
                 url: "x-apple.systempreferences:com.apple.Screen-Time-Settings.extension"),
        PrefPane(name: "Sharing", iconName: "square.and.arrow.up",
                 url: "x-apple.systempreferences:com.apple.Sharing-Settings.extension"),
        PrefPane(name: "Siri & Spotlight", iconName: "mic",
                 url: "x-apple.systempreferences:com.apple.Siri-Settings.extension"),
        PrefPane(name: "Software Update", iconName: "arrow.down.circle",
                 url: "x-apple.systempreferences:com.apple.Software-Update-Settings.extension"),
        PrefPane(name: "Sound", iconName: "speaker.wave.2",
                 url: "x-apple.systempreferences:com.apple.Sound-Settings.extension"),
        PrefPane(name: "Spotlight", iconName: "magnifyingglass",
                 url: "x-apple.systempreferences:com.apple.Spotlight-Settings.extension"),
        PrefPane(name: "Storage", iconName: "internaldrive",
                 url: "x-apple.systempreferences:com.apple.settings.Storage"),
        PrefPane(name: "Time Machine", iconName: "clock.arrow.circlepath",
                 url: "x-apple.systempreferences:com.apple.Time-Machine-Settings.extension"),
        PrefPane(name: "Touch ID & Password", iconName: "touchid",
                 url: "x-apple.systempreferences:com.apple.preferences.password"),
        PrefPane(name: "Trackpad", iconName: "rectangle.and.hand.point.up.left",
                 url: "x-apple.systempreferences:com.apple.Trackpad-Settings.extension"),
        PrefPane(name: "Users & Groups", iconName: "person.2",
                 url: "x-apple.systempreferences:com.apple.Users-Groups-Settings.extension"),
        PrefPane(name: "VPN", iconName: "lock.shield",
                 url: "x-apple.systempreferences:com.apple.VPN-Settings.extension"),
        PrefPane(name: "Wallet & Apple Pay", iconName: "creditcard",
                 url: "x-apple.systempreferences:com.apple.WalletSettingsExtension"),
        PrefPane(name: "Wallpaper", iconName: "photo",
                 url: "x-apple.systempreferences:com.apple.Wallpaper-Settings.extension"),
        PrefPane(name: "Wi-Fi", iconName: "wifi",
                 url: "x-apple.systempreferences:com.apple.wifi-settings-extension"),
    ]

    /// Fuzzy-search panes by name. Returns score-sorted matches.
    func search(query: String) -> [(pane: PrefPane, score: Int)] {
        let q = query.lowercased()
        return panes.compactMap { pane in
            let result = fuzzyMatch(query: q, target: pane.name)
            guard result.matched else { return nil }
            return (pane, result.score)
        }.sorted { $0.score > $1.score }
    }
}
