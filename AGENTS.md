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

`devices/<device>/packages.txt` is an optional second list, appended to the global one rather than overriding it — unlike the config tree, where a device file replaces the base file at the same path. A device without one installs exactly the global list. Only put a package there if a device genuinely must *not* have it; the default is global.

Whether to install is decided by hashing both lists into `$XDG_STATE_HOME/sleeyax-dotfiles/packages.sha256`. Adding a package to either therefore installs it on the next apply, with no flag needed; `--force` reinstalls regardless.

### Device Detection

`scripts/detect-device.sh` maps hostname to device name (`falcon` → desktop, `panda` → laptop). A manual override can be saved to `~/dotfiles/device` (gitignored).

### Hyprland Config Structure

Hyprland's config is Lua (`hl.*` API); the `.conf`/hyprlang format was dropped in Hyprland 0.57. The other `hypr*` tools still use hyprlang, so `hypridle.conf`, `hyprlock.conf` and `hyprsunset.conf` stay `.conf`.

The entrypoint `hyprland.lua` is a list of `require`s, with `~/.config/hypr/` as the `require` root. Each `conf/*.lua` is one flat file. ML4W shipped these as a `conf/<name>.lua` selector calling `load_variant()` to pick a file out of `conf/<name>s/`; with a single variant left per section that indirection bought nothing, so the variant is now the file. `conf/monitors.lua` is the generic fallback (`output = ""`), applied before the per-device `monitors.lua` narrows it.

Customised Hyprland configs live in `home/.config/hypr/` and `devices/*/.config/hypr/`:
- `monitors.lua` — monitor setup (per-device)
- `input.lua` — keyboard layout, pointer settings; laptop adds `hl.device()` blocks for AZERTY built-in vs QWERTY Planck (per-device)
- `gestures.lua` — touchpad swipes and pinches (laptop only; falcon has no touchpad)
- `conf/layouts.lua` — dwindle settings, workspace back-and-forth (base)
- `custom.lua` — autostart, window rules, visual tweaks; loaded last, so it wins over everything (base)
- `games.lua` — Steam game rules, `require`d from `custom.lua` (base)
- `conf/keybindings.lua` — every bind, then our unbinds/rebinds at the end (base)
- `conf/animations.lua` — animations off (base)

`custom.lua` and `games.lua` are files ML4W never shipped; `hyprland.lua` opt-in loads `custom.lua` if present. Since it is loaded last, it remains the cheapest place to put a change that has to win.

The base copies of `input.lua`, `monitors.lua` and `hypridle.conf` never deploy, because both devices override them. They are kept as the documented shape of a per-device file: adding a third device means copying one, not inventing it.

`gestures.lua` is laptop-only and lives only in `devices/laptop/`, so `hyprland.lua` guards its `require` the way it guards `custom.lua`.

Colors come from matugen (see **Colors** below), which writes both `colors.conf` and `colors.lua`. `colors.lua` defines bare globals loaded before `custom.lua`, so a palette entry is referenced as plain `inverse_primary`, not `$inverse_primary`.

The `hl` API is typed: `/usr/share/hypr/stubs/hl.meta.lua` (LuaLS stubs) and `/usr/share/hypr/hyprland.lua` (annotated example) are the authoritative references. `luac -p <file>` syntax-checks; `Hyprland --verify-config` validates the whole tree; `hyprctl configerrors` reports runtime errors.

### Colors

`~/.config/matugen/config.toml` maps each template in `matugen/templates/` to an output: `hypr/colors.lua`, `hypr/colors.conf`, `waybar/colors.css`, `rofi/colors.rasi`, `gtk-{3,4}.0/colors.css`, `btop/themes/matugen.theme`, and the rest. `ml4w-wallpaper` re-renders all of them on every wallpaper change.

**No matugen output is tracked under `home/`.** Stow folds at the directory level — `~/.config/waybar` is a symlink to `.stow/dotfiles/.config/waybar`, not a tree of per-file symlinks — so matugen writes into the generated `.stow/` tree and never touches the repo. Tracking a copy under `home/` therefore only ever produces a frozen snapshot that nothing reads. `apply.sh` copies the live palette into the tree it is about to rsync, since `rsync --delete` would otherwise wipe it on every apply.

Two consequences when adding a matugen output:
- Its directory has to exist in the stow tree, or `apply.sh` skips carrying the live copy across and `rsync --delete` wipes it on the next apply. `btop/themes/` and `ml4w/colors/` contain nothing but generated files, so they hold a `.gitkeep` to survive.
- A machine with no palette yet gets one from `ml4w/wallpapers/default.jpg` at the end of `apply.sh`. Missing outputs are fatal, not cosmetic: `hyprland.lua` does `require("colors")` and `hyprlock.conf` does `source = colors.conf`.

### Integrating a feature from a newer ML4W

The tree under `home/` was vendored from ML4W and is now ours. The base commit is the one named in README's opening paragraph; it is the merge base for any port.

```bash
BASE=f974938fd39382bc54816dcf5e76983239108914   # from README
git remote add ml4w https://github.com/mylinuxforwork/dotfiles.git   # first time only
git fetch ml4w 'refs/tags/*:refs/ml4w-tags/*' "$BASE"
```

Fetching upstream tags into `refs/ml4w-tags/*` rather than `refs/tags/*` keeps them out of `git tag` and out of anything pushed.

1. Read what changed upstream: `git diff "$BASE:dotfiles" ml4w-tags/<target>:dotfiles [-- <subpath>]`. Narrow with a subpath once you know where the feature lives.
2. Map paths: upstream `dotfiles/<p>` → `home/<p>`. Per-device variants live at `devices/desktop/<p>` and `devices/laptop/<p>`.
3. For each file, check whether we've modified it: `git diff "$BASE:dotfiles/<p>" "HEAD:home/<p>"`.
   - **Empty (untouched):** take upstream's copy wholesale — `git show ml4w-tags/<target>:dotfiles/<p> > home/<p>`.
   - **Non-empty (ours):** 3-way merge it, using the base as the ancestor, then resolve markers by hand. Our changes win on intent; upstream's win on new mechanism.
4. Check for device twins: `ls devices/*/<p>` — the same hunk usually has to be applied there too.
5. Update provenance: a **full** sync rewrites the version sentence in README. A **partial** port leaves it alone and adds a row to README's "Ported from later versions" table.
6. Verify: `./scripts/apply.sh`; `luac -p` every touched `.lua`; `Hyprland --verify-config`; `hyprctl configerrors`.

Never rewrite the recorded base commit to "fix" a diff — it describes history, not intent.

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
