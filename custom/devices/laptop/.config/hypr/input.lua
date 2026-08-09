-- -----------------------------------------------------
-- Input (laptop: AZERTY + QWERTY, toggled with ALT+SHIFT)
-- -----------------------------------------------------

hl.config({
    input = {
        kb_layout = "be,us",
        kb_variant = "",
        kb_model = "",
        kb_options = "grp:alt_shift_toggle",
        kb_rules = "",

        follow_mouse = 1,

        resolve_binds_by_sym = true,
        numlock_by_default   = true,

        accel_profile = "flat",
        sensitivity   = 0.4,

        touchpad = {
            natural_scroll = true,
        },
    },
})

-- External keyboard (Planck) always uses QWERTY
hl.device({
    name = "zsa-technology-labs-planck-ez-glow",
    kb_layout = "us",
    kb_variant = "",
})

-- Laptop keyboard always uses AZERTY
hl.device({
    name = "at-translated-set-2-keyboard",
    kb_layout = "be",
    kb_variant = "",
})
