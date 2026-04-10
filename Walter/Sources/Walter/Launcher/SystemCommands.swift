// SystemCommands.swift — Built-in system actions
//
// Hardcoded set of macOS system commands that mix into search results.
// "Restart" and "Shut Down" prompt for confirmation before executing.

import AppKit

struct SystemCommand {
    let name: String
    let subtitle: String
    let iconName: String        // SF Symbol name
    let action: () -> Void
    let needsConfirmation: Bool
}

class SystemCommands {

    private weak var config: ConfigManager?

    init(config: ConfigManager? = nil) {
        self.config = config
    }

    private var commands: [SystemCommand] {
        var cmds: [SystemCommand] = [
        SystemCommand(
            name: "Lock Screen",
            subtitle: "Lock the display",
            iconName: "lock",
            action: {
                // CGSession -suspend locks the screen
                Process.launchedProcess(launchPath: "/usr/bin/pmset", arguments: ["displaysleepnow"])
            },
            needsConfirmation: false
        ),
        SystemCommand(
            name: "Sleep",
            subtitle: "Put the Mac to sleep",
            iconName: "moon",
            action: {
                Process.launchedProcess(launchPath: "/usr/bin/pmset", arguments: ["sleepnow"])
            },
            needsConfirmation: false
        ),
        SystemCommand(
            name: "Restart",
            subtitle: "Restart this Mac",
            iconName: "arrow.clockwise",
            action: {
                let script = "tell application \"System Events\" to restart"
                NSAppleScript(source: script)?.executeAndReturnError(nil)
            },
            needsConfirmation: true
        ),
        SystemCommand(
            name: "Shut Down",
            subtitle: "Shut down this Mac",
            iconName: "power",
            action: {
                let script = "tell application \"System Events\" to shut down"
                NSAppleScript(source: script)?.executeAndReturnError(nil)
            },
            needsConfirmation: true
        ),
        SystemCommand(
            name: "Empty Trash",
            subtitle: "Permanently delete trashed files",
            iconName: "trash",
            action: {
                let script = "tell application \"Finder\" to empty the trash"
                NSAppleScript(source: script)?.executeAndReturnError(nil)
            },
            needsConfirmation: true
        ),
        SystemCommand(
            name: "Toggle Dark Mode",
            subtitle: "Switch between light and dark appearance",
            iconName: "circle.lefthalf.filled",
            action: {
                let script = """
                tell application "System Events"
                    tell appearance preferences
                        set dark mode to not dark mode
                    end tell
                end tell
                """
                NSAppleScript(source: script)?.executeAndReturnError(nil)
            },
            needsConfirmation: false
        ),
        SystemCommand(
            name: "Show Desktop",
            subtitle: "Move all windows aside",
            iconName: "rectangle.on.rectangle.slash",
            action: {
                let script = "tell application \"System Events\" to key code 103 using {command down, fn down}"
                NSAppleScript(source: script)?.executeAndReturnError(nil)
            },
            needsConfirmation: false
        ),
        SystemCommand(
            name: "Force Quit",
            subtitle: "Open the Force Quit window",
            iconName: "xmark.octagon",
            action: {
                let script = "tell application \"System Events\" to key code 12 using {command down, option down}"
                NSAppleScript(source: script)?.executeAndReturnError(nil)
            },
            needsConfirmation: false
        ),
        ]

        // "Open Config" — opens config.toml in the configured or auto-detected editor
        if let config = config {
            let configPath = config.configURL.path
            let editorPath = config.general.editor
            let editorName = Self.editorDisplayName(editorPath)

            cmds.append(SystemCommand(
                name: "Open Config",
                subtitle: "Edit Walter config in \(editorName)",
                iconName: "gearshape",
                action: {
                    Self.openInEditor(file: configPath, editor: editorPath)
                },
                needsConfirmation: false
            ))
        }

        return cmds
    }

    // MARK: - Editor detection

    /// Known text editors, checked in order of preference.
    /// Default: TextEdit (always exists). User can override with
    /// `editor = "/Applications/..."` in [general] config.
    private static let defaultEditor = "/System/Applications/TextEdit.app"

    private static func editorDisplayName(_ configuredEditor: String) -> String {
        let path = configuredEditor.isEmpty ? defaultEditor : configuredEditor
        return URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
    }

    private static func openInEditor(file: String, editor configuredEditor: String) {
        let editorPath = configuredEditor.isEmpty ? defaultEditor : configuredEditor
        NSWorkspace.shared.open(
            [URL(fileURLWithPath: file)],
            withApplicationAt: URL(fileURLWithPath: editorPath),
            configuration: NSWorkspace.OpenConfiguration()
        )
    }

    /// Fuzzy search system commands.
    func search(query: String) -> [(command: SystemCommand, score: Int)] {
        let q = query.lowercased()
        return commands.compactMap { cmd in
            let result = fuzzyMatch(query: q, target: cmd.name)
            guard result.matched else { return nil }
            return (cmd, result.score)
        }.sorted { $0.score > $1.score }
    }

    /// Shows a confirmation alert. Returns true if the user clicked OK.
    static func confirm(action name: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Are you sure?"
        alert.informativeText = "This will \(name.lowercased()) your Mac."
        alert.alertStyle = .warning
        alert.addButton(withTitle: name)
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }
}
