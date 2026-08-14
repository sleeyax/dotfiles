-- Loaded last by hyprland.lua, so everything here wins over the ML4W defaults.

hl.env("XCURSOR_THEME", "breeze_cursors")

-- Hyprland starts with a bare PATH, so keybinds and launchers would miss the wrappers in ~/.local/bin that the shell already picks up.
local user_bin = os.getenv("HOME") .. "/.local/bin"
local path = os.getenv("PATH") or ""
if not path:find(user_bin, 1, true) then
    hl.env("PATH", user_bin .. ":" .. path)
end

hl.on("hyprland.start", function()
    -- intentionally launches megasync twice so it goes to the tray
    -- see: https://github.com/meganz/MEGAsync/issues/161#issuecomment-797917923
    hl.exec_cmd("sleep 60; megasync")

    hl.exec_cmd("sleep 15; discord --start-minimized")
    hl.exec_cmd("sleep 5; slack --startup")
end)

hl.config({
    general = {
        border_size = 2,
        gaps_in = 2,
        gaps_out = 2,
        col = { active_border = inverse_primary },
    },

    -- disable opacity on all windows; it sucks
    decoration = {
        active_opacity = 1,
        inactive_opacity = 1,
        fullscreen_opacity = 1,
    },
})

-- route chat apps to workspace 9 silently on startup
for _, class in ipairs({ "^(discord)$", "^(Slack)$", [[^(org\.telegram\.desktop)$]] }) do
    hl.window_rule({
        match = { class = class },
        workspace = "9 silent",
    })
end

hl.window_rule({
    name = "windowrule-flameshot",
    match = { class = "(flameshot)" },
    move = { "0", "0" },
    pin = true,
    border_size = 0,
    stay_focused = true,
    float = true,
    opaque = true,
})

-- calendar top-right (overrides glass theme default of top-left)
hl.window_rule({
    name = "ml4w-calendar",
    match = { class = "(com.ml4w.calendar)" },
    float = true,
    move = { "(monitor_w*1)-window_w-20", "76" },
    pin = true,
    size = { "400", "400" },
})

-- jetbrains IDE popup fix
-- see: https://github.com/hyprwm/Hyprland/discussions/11981
hl.window_rule({
    name = "windowrule-jetbrains-popups",
    match = { class = [[^jetbrains-.+$]], float = true },
    stay_focused = true,
    no_initial_focus = true,
    no_follow_mouse = true,
})

require("games")
