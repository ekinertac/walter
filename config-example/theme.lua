-- Walter Lua theme override
-- Place at ~/.config/walter/theme.lua alongside config.toml.
-- Return a table with any subset of theme keys — missing keys fall back to
-- config.toml values. This file is evaluated fresh on every hot-reload.

local hour = tonumber(os.date("%H"))

-- Example: switch between light and dark palette based on time of day.
if hour >= 7 and hour < 18 then
  return {
    background    = "#eff1f5",   -- Catppuccin Latte
    foreground    = "#4c4f69",
    accent        = "#8839ef",
    border_radius = 10,
  }
else
  return {
    background    = "#1e1e2e",   -- Catppuccin Mocha
    foreground    = "#cdd6f4",
    accent        = "#cba6f7",
    border_radius = 12,
  }
end
