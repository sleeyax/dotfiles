local name = "default.lua"
load_variant(name, "keybindings")

-- free up SHIFT + S for flameshot; the special workspace moves to P
hl.unbind("SUPER + S")
hl.unbind("SUPER + SHIFT + S")

hl.bind("SUPER + P", hl.dsp.workspace.toggle_special("magic"),
    { description = "Toggle special workspace magic" })
hl.bind("SUPER + SHIFT + P", hl.dsp.exec_cmd("~/.config/ml4w/scripts/ml4w-toggle-scratchpad-window"),
    { description = "Toggle window in/out of special workspace magic" })

-- screenshot.sh needs grimblast, which we deliberately don't install; flameshot takes its place
hl.unbind("SUPER + PRINT")
hl.unbind("SUPER + ALT + S")

hl.bind("SUPER + SHIFT + S", hl.dsp.exec_cmd("QT_SCALE_FACTOR=0.8335 flameshot gui"),
    { description = "Take a screenshot" })

-- upstream binds this to a config reload, which SUPER + CTRL + R already does
hl.unbind("SUPER + SHIFT + R")

hl.bind("SUPER + SHIFT + R", hl.dsp.exec_cmd("kooha"),
    { description = "Record the screen" })

hl.bind("SUPER + K", hl.dsp.exec_cmd("code"),
    { description = "Launch Visual Studio Code" })

-- deps: handy-bin (AUR), wtype
-- wtype is what types the transcript into Wayland windows; without it handy falls back to enigo's X11 backend and the keystrokes only ever reach XWayland clients
hl.bind("SUPER + O", hl.dsp.exec_cmd("handy --toggle-transcription"),
    { description = "Toggle voice transcription" })
