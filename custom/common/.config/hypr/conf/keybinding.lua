local name = "default.lua"
load_variant(name, "keybindings")

-- free up SHIFT + S for flameshot; the special workspace moves to P
hl.unbind("SUPER + S")
hl.unbind("SUPER + SHIFT + S")

hl.bind("SUPER + P", hl.dsp.workspace.toggle_special("magic"),
    { description = "Toggle special workspace magic" })
hl.bind("SUPER + SHIFT + P", hl.dsp.exec_cmd("~/.config/ml4w/scripts/ml4w-toggle-scratchpad-window"),
    { description = "Toggle window in/out of special workspace magic" })

-- upstream's screenshot.sh needs grimblast, which isn't installed
hl.unbind("SUPER + PRINT")
hl.unbind("SUPER + ALT + S")

hl.bind("SUPER + SHIFT + S", hl.dsp.exec_cmd("flameshot gui"),
    { description = "Take a screenshot" })

-- deps: handy-bin (AUR), wtype
-- wtype is what types the transcript into Wayland windows; without it handy falls back to enigo's X11 backend and the keystrokes only ever reach XWayland clients
hl.bind("SUPER + O", hl.dsp.exec_cmd("handy --toggle-transcription"),
    { description = "Toggle voice transcription" })
