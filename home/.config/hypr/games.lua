-- Launch steam games in fullscreen on monitor 1 and workspace 10
hl.window_rule({
    name = "windowrule-steam-games",
    match = { class = [[^steam_app_\d+$]] },
    fullscreen = true,
    monitor = "1",
    workspace = "10",
})

hl.workspace_rule({
    workspace = "10",
    no_border = true,
    no_rounding = true,
})
