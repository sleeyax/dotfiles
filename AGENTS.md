# AGENTS.md

This file provides guidance to AI agents when working with code in this repository.

## Overview

Personal Hyprland dotfiles for Arch Linux, based on [ML4W](https://github.com/mylinuxforwork/dotfiles). Manages configuration across two devices (desktop "falcon" and laptop "panda") using GNU Stow.

## Key Commands

```bash
./scripts/apply.sh          # Auto-detect device by hostname, merge configs, deploy via stow
./scripts/apply.sh --force  # Reinstall all dependencies (ML4W base + stow)
./scripts/set-device.sh desktop  # Manually switch to desktop config
./scripts/set-device.sh laptop   # Manually switch to laptop config
./scripts/update.sh <tag>        # Update upstream ML4W submodule to a specific release tag
```

## Architecture

### Layered Override System

Configs are merged in order: **upstream → common → device-specific**, where later layers override earlier ones.

```
upstream/dotfiles/              # ML4W base (git submodule - never edit directly)
custom/common/                  # Shared overrides for all devices
custom/devices/desktop/         # falcon-specific (QWERTY, 4K DP-5 @ 144Hz, scale 1.2)
custom/devices/laptop/          # panda-specific (AZERTY + QWERTY toggle, eDP-1, gestures)
```

The `apply.sh` script copies upstream, overlays common, then overlays device configs into `.stow/dotfiles/`, and runs `stow -t $HOME --restow dotfiles` to symlink everything into `$HOME`.

### Device Detection

`scripts/detect-device.sh` maps hostname to device name (`falcon` → desktop, `panda` → laptop). A manual override can be saved to `~/dotfiles/device` (gitignored).

### Hyprland Config Structure

Hyprland's config is Lua (`hl.*` API); the `.conf`/hyprlang format was dropped in Hyprland 0.57. The other `hypr*` tools still use hyprlang, so `hypridle.conf`, `hyprlock.conf`, `hyprpaper.conf` and `hyprsunset.conf` stay `.conf`.

Upstream's entrypoint `hyprland.lua` is a list of `require`s. The `require` root is `~/.config/hypr/`, and `functions.lua` defines a global `load_variant(file, dir)` that the `conf/<name>.lua` selector files use to pull a variant out of `conf/<name>s/`.

Custom configs live in `custom/{common,devices/*}/.config/hypr/`:
- `monitors.lua` — monitor setup (per-device)
- `input.lua` — keyboard layout, pointer settings; laptop adds `hl.device()` blocks for AZERTY built-in vs QWERTY Planck (per-device)
- `conf/layout.lua` — picks the `default`/`laptop` layout variant, enables workspace back-and-forth (per-device; the `laptop` variant also supplies the 3-finger swipe)
- `custom.lua` — autostart, window rules, visual tweaks; loaded last, so it wins over everything (common)
- `games.lua` — Steam game rules, `require`d from `custom.lua` (common)
- `conf/keybinding.lua` — loads upstream's variant, then unbinds/rebinds (common)
- `conf/animation.lua` — selects the `disabled` animation variant (common)

Override points to prefer: `custom.lua` is **not shipped** upstream (`hyprland.lua` opt-in loads it if present), so it can never be clobbered by a submodule bump. `input.lua` and `monitors.lua` are the files upstream itself marks user-owned.

Colors come from matugen, which writes both `colors.conf` and `colors.lua`. `colors.lua` defines bare globals loaded before `custom.lua`, so a palette entry is referenced as plain `inverse_primary`, not `$inverse_primary`.

The `hl` API is typed: `/usr/share/hypr/stubs/hl.meta.lua` (LuaLS stubs) and `/usr/share/hypr/hyprland.lua` (annotated example) are the authoritative references. `luac -p <file>` syntax-checks; `Hyprland --verify-config` validates the whole tree; `hyprctl configerrors` reports runtime errors.

### Web Apps

`scripts/install-webapp.py` installs a site as a Chromium web app in its own user-data directory; see **Web apps** in [README.md](README.md) for usage. It writes to `$HOME` only — nothing enters the stow tree, since the profiles hold live logins.

### Shell Configuration

Zsh configs in `custom/common/.config/zshrc/` are numbered for load order (`00-init`, `25-aliases`). Init sets up NVM, PATH (cargo, go), and `EDITOR=code`. Aliases include eza-based ls/ll/lt, hyprlock, nmtui, and ML4W app shortcuts.

## Devices

| Device  | Hostname | Keyboard    | Monitor            | Idle: Lock/Off/Suspend |
|---------|----------|-------------|--------------------|------------------------|
| Desktop | falcon   | QWERTY (us) | DP-5 3840x2160@144 | 10m / 11m / never      |
| Laptop  | panda    | AZERTY (be) | eDP-1              | 10m / 15m / 30m        |
