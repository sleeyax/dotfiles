local name = "default.lua"
load_variant(name, "keybindings")

-- free up S for flameshot; the special workspace moves to P
hl.unbind("SUPER + S")
hl.unbind("SUPER + SHIFT + S")

hl.bind("SUPER + P", hl.dsp.workspace.toggle_special("magic"),
    { description = "Toggle special workspace magic" })
hl.bind("SUPER + SHIFT + P", hl.dsp.exec_cmd("~/.config/ml4w/scripts/ml4w-toggle-scratchpad-window"),
    { description = "Toggle window in/out of special workspace magic" })

-- flameshot everywhere; upstream's screenshot.sh needs grimblast, which isn't installed
local flameshot = "QT_SCALE_FACTOR=0.8335 flameshot gui"

hl.unbind("SUPER + PRINT")
hl.unbind("SUPER + ALT + S")

hl.bind("SUPER + S", hl.dsp.exec_cmd(flameshot), { description = "Take a screenshot" })
hl.bind("SUPER + SHIFT + S", hl.dsp.exec_cmd(flameshot), { description = "Take a screenshot" })
hl.bind("SUPER + PRINT", hl.dsp.exec_cmd(flameshot), { description = "Take a screenshot" })
hl.bind("SUPER + ALT + S", hl.dsp.exec_cmd(flameshot), { description = "Take a screenshot" })

-- deps: handy-bin (AUR), wtype
-- wtype is what types the transcript into Wayland windows; without it handy falls back to enigo's X11 backend and the keystrokes only ever reach XWayland clients
hl.bind("SUPER + O", hl.dsp.exec_cmd("handy --toggle-transcription"),
    { description = "Toggle voice transcription" })
