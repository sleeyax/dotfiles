-- Advanced configuration for Hyprland

-- MONITORS
require("conf.monitors")
require("monitors")

-- INPUT
require("input")

-- GESTURE
-- Only devices with a touchpad ship a gestures.lua.
local g = io.open(os.getenv("HOME") .. "/.config/hypr/gestures.lua", "r")
if g then
    g:close()
    require("gestures")
end

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
