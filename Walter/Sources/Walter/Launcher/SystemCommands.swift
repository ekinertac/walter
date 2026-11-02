import AppKit

class SystemCommands {

    // MARK: - Editor detection

    /// Editors checked in order when `[general] editor` is not set. The
    /// first one whose .app bundle exists on disk wins; if none of them
    /// are installed we fall back to TextEdit, which always ships with macOS.
    private static let editorCandidates: [String] = [
        "/Applications/CotEditor.app",
        "/Applications/BBEdit.app",
        "/Applications/Sublime Text.app",
        "/Applications/Visual Studio Code.app",
        "/Applications/Cursor.app",
        "/Applications/Zed.app",
        "/Applications/Zed Preview.app",
        "/Applications/Nova.app",
        "/Applications/MacVim.app",
        "/System/Applications/TextEdit.app",
    ]

    /// Resolves the editor path from `[general] editor` if set; otherwise
    /// scans `editorCandidates` for the first installed app.
    static func resolveEditorPath(configured: String) -> String {
        if !configured.isEmpty,
           FileManager.default.fileExists(atPath: configured) {
            return configured
        }
        for candidate in editorCandidates {
            if FileManager.default.fileExists(atPath: candidate) {
                return candidate
            }
        }
        // Last-ditch — TextEdit ships with every macOS install.
        return "/System/Applications/TextEdit.app"
    }

}
