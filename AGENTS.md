# AGENTS.md

This file provides guidance to AI agents when working with code in this repository.

## Overview

Personal Hyprland dotfiles for Arch Linux, originally based on [ML4W](https://github.com/mylinuxforwork/dotfiles) and vendored since. Manages configuration across two devices (desktop "falcon" and laptop "panda") using GNU Stow.

## Key Commands

```bash
./scripts/apply.sh          # Auto-detect device by hostname, merge configs, deploy via stow
./scripts/apply.sh --force  # Reinstall all packages
./scripts/set-device.sh desktop  # Manually switch to desktop config
./scripts/set-device.sh laptop   # Manually switch to laptop config
./scripts/ml4w.sh status         # What we've changed relative to the vendored ML4W base
```

## Architecture

### Layered Override System

Configs are merged in order: **base → device-specific**, where the device layer overrides the base.

```
home/                           # The base tree, ours to edit; maps 1:1 to $HOME
devices/desktop/                # falcon-specific (QWERTY, 4K DP-5 @ 144Hz, scale 1.2)
devices/laptop/                 # panda-specific (AZERTY + QWERTY toggle, eDP-1, gestures)
```

The `apply.sh` script copies `home/`, overlays device configs into `.stow/dotfiles/`, and runs `stow -t $HOME --restow dotfiles` to symlink everything into `$HOME`.

There is no "common" layer: shared customisations are edits to `home/` itself. A file only belongs in `devices/` if the two machines genuinely need different content.

### Packages

`setup/packages.txt` is the package list, one per line with `#` comments, grouped by subsystem. `apply.sh` installs it with `yay`/`paru`.

Whether to install is decided by hashing that file into `$XDG_STATE_HOME/sleeyax-dotfiles/packages.sha256`. Adding a package therefore installs it on the next apply, with no flag needed; `--force` reinstalls regardless.

### Device Detection

`scripts/detect-device.sh` maps hostname to device name (`falcon` → desktop, `panda` → laptop). A manual override can be saved to `~/dotfiles/device` (gitignored).

### Hyprland Config Structure

Hyprland's config is Lua (`hl.*` API); the `.conf`/hyprlang format was dropped in Hyprland 0.57. The other `hypr*` tools still use hyprlang, so `hypridle.conf`, `hyprlock.conf` and `hyprsunset.conf` stay `.conf`.

The entrypoint `hyprland.lua` is a list of `require`s. The `require` root is `~/.config/hypr/`, and `functions.lua` defines a global `load_variant(file, dir)` that the `conf/<name>.lua` selector files use to pull a variant out of `conf/<name>s/`.

Customised Hyprland configs live in `home/.config/hypr/` and `devices/*/.config/hypr/`:
- `monitors.lua` — monitor setup (per-device)
- `input.lua` — keyboard layout, pointer settings; laptop adds `hl.device()` blocks for AZERTY built-in vs QWERTY Planck (per-device)
- `conf/layout.lua` — picks the `default` layout variant, enables workspace back-and-forth (base)
- `custom.lua` — autostart, window rules, visual tweaks; loaded last, so it wins over everything (base)
- `games.lua` — Steam game rules, `require`d from `custom.lua` (base)
- `conf/keybinding.lua` — loads the keybinding variant, then unbinds/rebinds (base)
- `conf/animation.lua` — selects the `disabled` animation variant (base)

`custom.lua` and `games.lua` are files ML4W never shipped; `hyprland.lua` opt-in loads `custom.lua` if present. Since it is loaded last, it remains the cheapest place to put a change that has to win.

The base copies of `input.lua`, `monitors.lua` and `hypridle.conf` never deploy, because both devices override them. They are kept anyway: `gestures.lua` is laptop-only, so the base tree is not uniformly dead here.

Colors come from matugen (see **Colors** below), which writes both `colors.conf` and `colors.lua`. `colors.lua` defines bare globals loaded before `custom.lua`, so a palette entry is referenced as plain `inverse_primary`, not `$inverse_primary`.

The `hl` API is typed: `/usr/share/hypr/stubs/hl.meta.lua` (LuaLS stubs) and `/usr/share/hypr/hyprland.lua` (annotated example) are the authoritative references. `luac -p <file>` syntax-checks; `Hyprland --verify-config` validates the whole tree; `hyprctl configerrors` reports runtime errors.

### Colors

`~/.config/matugen/config.toml` maps each template in `matugen/templates/` to an output: `hypr/colors.lua`, `hypr/colors.conf`, `waybar/colors.css`, `rofi/colors.rasi`, `gtk-{3,4}.0/colors.css`, `btop/themes/matugen.theme`, and the rest. `ml4w-wallpaper` re-renders all of them on every wallpaper change.

**No matugen output is tracked under `home/`.** Stow folds at the directory level — `~/.config/waybar` is a symlink to `.stow/dotfiles/.config/waybar`, not a tree of per-file symlinks — so matugen writes into the generated `.stow/` tree and never touches the repo. Tracking a copy under `home/` therefore only ever produces a frozen snapshot that nothing reads. `apply.sh` copies the live palette into the tree it is about to rsync, since `rsync --delete` would otherwise wipe it on every apply.

Two consequences when adding a matugen output:
- Its directory has to exist in the stow tree, or `apply.sh` skips carrying the live copy across and `rsync --delete` wipes it on the next apply. `btop/themes/` and `ml4w/colors/` contain nothing but generated files, so they hold a `.gitkeep` to survive.
- A machine with no palette yet gets one from `ml4w/wallpapers/default.jpg` at the end of `apply.sh`. Missing outputs are fatal, not cosmetic: `hyprland.lua` does `require("colors")` and `hyprlock.conf` does `source = colors.conf`.

### Integrating a feature from a newer ML4W

The tree under `home/` was vendored from ML4W and is now ours. `ml4w-base.env` records the commit it came from; that commit is the merge base for porting.

1. `./scripts/ml4w.sh sync` — fetch ML4W (creates the `ml4w` remote on first run).
2. `./scripts/ml4w.sh tags` — confirm the target version exists.
3. `./scripts/ml4w.sh diff base <target> [subpath]` — read what changed upstream. Narrow with a subpath (e.g. `.config/waybar`) once you know where the feature lives.
4. Map paths: upstream `dotfiles/<p>` → `home/<p>`. Per-device variants live at `devices/desktop/<p>` and `devices/laptop/<p>`.
5. For each file, check whether we've modified it: `./scripts/ml4w.sh status <p>`.
   - **Empty (untouched):** `./scripts/ml4w.sh take <target> <p>`.
   - **Non-empty (ours):** `./scripts/ml4w.sh port <target> <p>`, then resolve conflict markers by hand. Our changes win on intent; upstream's win on new mechanism.
6. Check for device twins: `ls devices/*/<p>` — the same hunk usually has to be applied there too.
7. Update provenance: a **full** sync bumps `ML4W_TAG`/`ML4W_COMMIT`/`ML4W_DATE` in `ml4w-base.env` *and* the version sentence in README. A **partial** port leaves `ml4w-base.env` alone and adds a row to README's "Ported from later versions" table.
8. Verify: `./scripts/apply.sh`; `luac -p` every touched `.lua`; `Hyprland --verify-config`; `hyprctl configerrors`.

Never edit `ml4w-base.env` to "fix" a diff — it describes history, not intent.

### Web Apps

`scripts/install-webapp.py` installs a site as a Chromium web app in its own user-data directory; see **Web apps** in [README.md](README.md) for usage. It writes to `$HOME` only — nothing enters the stow tree, since the profiles hold live logins.

### Shell Configuration

Zsh configs in `home/.config/zshrc/` are numbered for load order (`00-init`, `20-customization`, `25-aliases`). Init sets up NVM, PATH (cargo, go), and `EDITOR=code`. Aliases include eza-based ls/ll/lt, hyprlock, nmtui, and ML4W app shortcuts.

`.zshrc` sources those in order and then `~/.zshrc_custom`, which is the only supported place for machine-local, uncommitted shell config. It has to sit in `$HOME`: `~/.config/zshrc` is a stow symlink into `.stow/`, so anything added under it is destroyed by the `rsync --delete` in `apply.sh`.

## Devices

| Device  | Hostname | Keyboard    | Monitor            | Idle: Lock/Off/Suspend |
|---------|----------|-------------|--------------------|------------------------|
| Desktop | falcon   | QWERTY (us) | DP-5 3840x2160@144 | 10m / 11m / never      |
| Laptop  | panda    | AZERTY (be) | eDP-1              | 10m / 15m / 30m        |
