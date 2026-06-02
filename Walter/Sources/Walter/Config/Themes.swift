// Themes.swift — Built-in theme presets
//
// Each theme defines background, foreground, and accent colors.
// User sets `name = "dracula"` in [theme] section of config.toml.
// When a theme name is set, individual color values are ignored.

import Foundation

struct ThemePreset {
    let background: String
    let foreground: String
    let accent: String
    // Optional palette extensions. Built-in presets leave these nil and
    // let the UI derive selection/subtitle/border from the core three.
    // User `.theme` files may set them explicitly.
    var selection: String? = nil
    var subtitle: String? = nil
    var border: String? = nil
}

let builtinThemes: [String: ThemePreset] = [

    // Default — matches macOS system vibrancy (no tinted background)
    "spotlight": ThemePreset(
        background: "#00000000", foreground: "#ffffff", accent: "#007aff"),

    // Dark themes
    "catppuccin-mocha": ThemePreset(
        background: "#1e1e2e", foreground: "#cdd6f4", accent: "#cba6f7"),
    "catppuccin-macchiato": ThemePreset(
        background: "#24273a", foreground: "#cad3f5", accent: "#c6a0f6"),
    "catppuccin-frappe": ThemePreset(
        background: "#303446", foreground: "#c6d0f5", accent: "#ca9ee6"),
    "nord": ThemePreset(
        background: "#2e3440", foreground: "#eceff4", accent: "#88c0d0"),
    "dracula": ThemePreset(
        background: "#282a36", foreground: "#f8f8f2", accent: "#bd93f9"),
    "gruvbox": ThemePreset(
        background: "#282828", foreground: "#ebdbb2", accent: "#fabd2f"),
    "solarized-dark": ThemePreset(
        background: "#002b36", foreground: "#839496", accent: "#268bd2"),
    "rose-pine": ThemePreset(
        background: "#191724", foreground: "#e0def4", accent: "#c4a7e7"),
    "rose-pine-moon": ThemePreset(
        background: "#232136", foreground: "#e0def4", accent: "#c4a7e7"),
    "tokyo-night": ThemePreset(
        background: "#1a1b26", foreground: "#a9b1d6", accent: "#7aa2f7"),
    "one-dark": ThemePreset(
        background: "#282c34", foreground: "#abb2bf", accent: "#c678dd"),
    "kanagawa": ThemePreset(
        background: "#1f1f28", foreground: "#dcd7ba", accent: "#957fb8"),
    "everforest": ThemePreset(
        background: "#2d353b", foreground: "#d3c6aa", accent: "#a7c080"),
    "ayu-dark": ThemePreset(
        background: "#0d1017", foreground: "#bfbdb6", accent: "#e6b450"),

    // Light themes
    "catppuccin-latte": ThemePreset(
        background: "#eff1f5", foreground: "#4c4f69", accent: "#8839ef"),
    "solarized-light": ThemePreset(
        background: "#fdf6e3", foreground: "#657b83", accent: "#268bd2"),
    "github-light": ThemePreset(
        background: "#ffffff", foreground: "#24292f", accent: "#0969da"),
    "rose-pine-dawn": ThemePreset(
        background: "#faf4ed", foreground: "#575279", accent: "#907aa9"),
    "ayu-light": ThemePreset(
        background: "#fcfcfc", foreground: "#5c6166", accent: "#ff9940"),
    "everforest-light": ThemePreset(
        background: "#fdf6e3", foreground: "#5c6a72", accent: "#8da101"),
]
