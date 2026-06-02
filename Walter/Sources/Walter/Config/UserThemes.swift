// UserThemes.swift — Loads custom themes from ~/.config/walter/themes/
//
// Each theme is a plain-text file with the extension `.theme`. The
// filename (sans extension) is the theme's name, so a file at
//   ~/.config/walter/themes/cyberpunk.theme
// adds a theme called "cyberpunk" that the user can select via the
// theme picker or by writing `name = "cyberpunk"` in the [theme]
// section of config.toml.
//
// File format — three whitespace-separated key/value lines, in any
// order. Lines starting with `#` are comments. Only `background`,
// `foreground`, and `accent` are read; everything else is ignored.
//
//   # cyberpunk.theme
//   background #0a0a23
//   foreground #00ffff
//   accent     #ff00ff
//
// Called by: ConfigManager during load(); the merged theme map (built-in
// + user) is consulted whenever the [theme].name key resolves a preset.
// Related: Themes.swift (built-in presets), ConfigManager.swift.

import Foundation

func loadUserThemes(from dir: URL) -> [String: ThemePreset] {
    let fm = FileManager.default
    guard let files = try? fm.contentsOfDirectory(
        at: dir,
        includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles]
    ) else {
        return [:]
    }

    var themes: [String: ThemePreset] = [:]
    for url in files where url.pathExtension == "theme" {
        let name = url.deletingPathExtension().lastPathComponent.lowercased()
        guard let preset = parseThemeFile(at: url) else {
            print("UserThemes: skipped \(url.lastPathComponent) (incomplete or unreadable)")
            continue
        }
        themes[name] = preset
    }

    if !themes.isEmpty {
        print("UserThemes: loaded \(themes.count) custom theme(s) from \(dir.path)")
    }
    return themes
}

private func parseThemeFile(at url: URL) -> ThemePreset? {
    guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }

    var bg: String?, fg: String?, accent: String?
    var selection: String?, subtitle: String?, border: String?

    for rawLine in content.components(separatedBy: .newlines) {
        // Strip everything after `#` — comments.
        var line = rawLine
        if let hashIdx = line.firstIndex(of: "#") {
            line = String(line[..<hashIdx])
        }
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { continue }

        // Tokenise on whitespace; first token is the key, rest is the value.
        let tokens = trimmed.split(whereSeparator: { $0.isWhitespace })
        guard tokens.count >= 2 else { continue }
        let key = String(tokens[0]).lowercased()
        let value = String(tokens[1])

        switch key {
        case "background", "bg":      bg = value
        case "foreground", "fg":      fg = value
        case "accent":                accent = value
        case "selection":             selection = value
        case "subtitle":              subtitle = value
        case "border":                border = value
        default: break
        }
    }

    guard let bg, let fg, let accent else { return nil }
    return ThemePreset(background: bg, foreground: fg, accent: accent,
                       selection: selection, subtitle: subtitle, border: border)
}
