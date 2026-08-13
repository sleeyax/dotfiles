-- Advanced configuration for Hyprland

-- MONITORS
require("conf.monitors")
require("monitors")

-- INPUT
require("input")

-- GESTURE
require("gestures")

-- AUTOSTART
require("conf.autostart")

-- COLORS
require("colors")

-- CONFIGURATION
require("conf.windows")
require("conf.decorations")
require("conf.layouts")
require("conf.misc")
require("conf.keybindings")
require("conf.animations")
require("conf.ml4w")

-- CUSTOM
local f = io.open(os.getenv("HOME") .. "/.config/hypr/custom.lua", "r")
if f then
    f:close()
    require("custom")
end
