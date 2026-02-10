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

Custom Hyprland configs live in `custom/{common,devices/*}/.config/hypr/conf/` and override the upstream equivalents:
- `device.conf` — monitor, input device settings (per-device)
- `keyboard.conf` — keyboard layout (laptop only: AZERTY + Planck external keyboard)
- `layout.conf` — workspace gestures (laptop), game workspace rules (desktop)
- `custom.conf` — autostart apps, window rules, visual tweaks (common)
- `keybinding.conf` — hotkey overrides (common)
- `animation.conf`, `cursor.conf` — visual settings (common)

### Shell Configuration

Zsh configs in `custom/common/.config/zshrc/` are numbered for load order (`00-init`, `25-aliases`). Init sets up NVM, PATH (cargo, go), and `EDITOR=code`. Aliases include eza-based ls/ll/lt, hyprlock, nmtui, and ML4W app shortcuts.

## Devices

| Device  | Hostname | Keyboard    | Monitor            | Idle: Lock/Off/Suspend |
|---------|----------|-------------|--------------------|------------------------|
| Desktop | falcon   | QWERTY (us) | DP-5 3840x2160@144 | 10m / 11m / never      |
| Laptop  | panda    | AZERTY (be) | eDP-1              | 10m / 15m / 30m        |
