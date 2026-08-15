-- Loaded last by hyprland.lua, so everything here wins over the ML4W defaults.

hl.env("XCURSOR_THEME", "breeze_cursors")

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
