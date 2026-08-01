local name = "default.lua"
load_variant(name, "keybindings")

-- free up S for flameshot; the special workspace moves to P
hl.unbind("SUPER + S")
hl.unbind("SUPER + SHIFT + S")

hl.bind("SUPER + P", hl.dsp.workspace.toggle_special("magic"),
    { description = "Toggle special workspace magic" })
hl.bind("SUPER + SHIFT + P", hl.dsp.exec_cmd("~/.config/ml4w/scripts/ml4w-toggle-scratchpad-window"),
    { description = "Toggle window in/out of special workspace magic" })

hl.bind("SUPER + S", hl.dsp.exec_cmd("QT_SCALE_FACTOR=0.8335 flameshot gui"),
    { description = "Take a screenshot" })
hl.bind("SUPER + SHIFT + S", hl.dsp.exec_cmd("QT_SCALE_FACTOR=0.8335 flameshot gui"),
    { description = "Take a screenshot" })
