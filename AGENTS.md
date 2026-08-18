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

`setup/packages.<device>.txt` is an optional second list, appended to the global one rather than overriding it — unlike the config tree, where a device file replaces the base file at the same path. A device without one installs exactly the global list. Only put a package there if a device genuinely must *not* have it; the default is global.

It lives in `setup/` and not `devices/<device>/` because `apply.sh` copies everything under `devices/<device>/` into the stow tree verbatim; a package list there would be symlinked into `$HOME`.

Whether to install is decided by hashing both lists into `$XDG_STATE_HOME/sleeyax-dotfiles/packages.sha256`. Adding a package to either therefore installs it on the next apply, with no flag needed; `--force` reinstalls regardless.

### Services

Installing a package is not the same as enabling its unit, and `apply.sh` enables the handful that have to be running before the session rather than on demand.
The list is the `SERVICES` array in `apply.sh` itself: with one entry, a `setup/services.txt` alongside the package lists would buy nothing.
`enable_services` skips whatever `systemctl is-enabled` already reports, so a normal apply never prompts for sudo.

Only a unit whose *timing* matters belongs here.
`power-profiles-daemon` is the case that forced it: it ships D-Bus activated, waybar's power-profiles module is what triggers the activation, and that module segfaults when the call lands in the window where the display manager's greeter session is tearing its bus connections down.
The race is won on most boots and lost on a slow one, which makes it look like a change when nothing changed.

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

### Waybar

Every module definition lives in the single `home/.config/waybar/modules.json`, including the custom ones.
A theme's `config` only picks which modules appear and in what order.
`launch.sh` `sed`s a fixed few of those entries out of the theme `config` by exact string, so each name stays on its own line in the canonical `"name",` form.

`modules.json` is JSONC: it has `//` comments and a trailing comma, so `jq` cannot parse it and waybar is the only parser. Run waybar in the foreground to see a syntax error.

**Signal registry.** `signal: N` makes a module re-exec on `SIGRTMIN+N`, and the numbers are global to the bar, so a new module takes the next free one:

| Signal | Module | Fired from |
| ------ | ------ | ---------- |
| 1 | `custom/updates` | `ml4w/settings/install-updates.sh` |
| 2 | `custom/claude-usage` | `waybar/scripts/claude-usage.sh feed` |

`SIGUSR2` is different in kind: it resets the whole bar rather than re-execing one module, so every module blinks out and back and the widths around them shift while they refill. Only `ml4w/scripts/ml4w-wallpaper` fires it, where a palette change makes the reset worth it; nothing on a timer may.

`reload_style_on_change` is the one that costs nothing: waybar watches the stylesheet, and reloads the style provider alone without touching a module. It resolves an `@import` against its own config directories and never against the importing file, so an import it is meant to watch has to be an absolute path — see **Drawing with images** below.

`escape: true` escapes Pango markup, which is right for a module printing arbitrary text and wrong for one drawing with markup. A module that draws leaves it off and escapes its own interpolations instead — or, as `claude-usage.sh` does, interpolates nothing but generated integers and fixed labels.

**Module state never goes under a stow-folded config dir.** `~/.config/waybar` and `~/.config/hypr` are symlinks into `.stow/dotfiles/`, which `apply.sh` runs `rsync -a --delete` over, so a cache written beside the script is destroyed on the next apply. Write to `${XDG_CACHE_HOME:-$HOME/.cache}` instead. (This is the general form of the rule in **Preserved files** below.)

`claude-usage.sh` is a pure renderer and makes no network calls. Its only data source is `home/.claude/statusline.sh`, which pipes the statusline payload into `claude-usage.sh feed` because the `statusLine` command is the one place Claude Code exposes `rate_limits`.

**Drawing with images.** The module has no text beyond spaces: three `background-image` layers are painted over them. The first is `waybar/claude.svg`, a tracked asset: the Claude mark from Simple Icons, recoloured, and drawn at 18px against the rings' 16px so it reads as the label rather than a third gauge. The other two are the usage rings. No font glyph fills continuously — the closest, `nf-md-circle_slice_1..8`, quantises to eighths — so an exact percentage has to be drawn.

Four things follow, and they are the price of the exact fill:
- **The script owns the colour.** An image cannot inherit the module's CSS `color:`, so `claude-usage.sh` resolves `on_surface`/`tertiary`/`error` out of `~/.config/waybar/colors.css` itself and writes the hex into the SVG. A wallpaper change rewrites that palette silently, so the colour is re-read every render and the rings catch up within one `interval`.
- **The script owns the declaration too, not just the images.** GTK caches the decoded image in the style provider and would keep painting it over rewritten bytes, so a redrawn ring has to arrive under a name GTK has never seen. `claude-usage.sh` therefore names each ring after what it draws (`ring-<pct>-<hex>.svg`) and generates the whole `background-image` block into `$XDG_CACHE_HOME/claude-usage/rings.css`, which `themes/ml4w-modern/default/style.css` `@import`s and waybar reloads on change. Nothing about the layers belongs in the theme's `style.css`, since a rule there would override the generated one.
- **That import is absolute, and the tracked copy is a placeholder.** Waybar resolves an `@import` against its own config directories rather than against the importing file, and only watches what it resolves. The tracked stylesheet carries `$XDG_CACHE_HOME`, which `apply.sh` expands while staging — the same arrangement as `bookmarks` under **Preserved files**, and unusable as-is if `home/` is stowed by hand. `launch.sh` renders the fragment before starting the bar, because waybar builds its watch list once from the imports that resolved at parse time.
- **The text holds the space open, not the padding.** A label's hit region follows its text, so anything sitting over CSS padding is unhoverable — with padding, only the glyph the module used to draw took hover, and the tooltip came with it. The module therefore has no horizontal padding at all: the script emits nine non-breaking spaces, one per 9.6px at `font-size: 16px`, and the images are painted over them at fixed pixel offsets. The spaces are non-breaking because Pango may drop ordinary ones at an edge, and the `font-family` rule below is load-bearing for the same reason — their advance is the whole layout. Changing the font, its size, or the spacer count means re-measuring the offsets.
- Anything hover-related on this module must set `background-color`, never the `background` shorthand: the shorthand resets `background-image` and the rings vanish on hover.

`home/.claude/` holds `statusline.sh` and nothing else — no `settings.json`, no credentials, no agents.
`apply.sh` runs `mkdir -p "$HOME/.claude"` *before* stowing for the folding reason above: without it, stow would make `~/.claude` a symlink into `.stow/` and Claude Code's own state would land there.
(The `mkdir -p "$HOME/.mydotfiles"` further down is the same idea but runs after stow, since nothing is stowed into it.)

### Colors

`~/.config/matugen/config.toml` maps each template in `matugen/templates/` to an output: `hypr/colors.lua`, `hypr/colors.conf`, `waybar/colors.css`, `rofi/colors.rasi`, `gtk-{3,4}.0/colors.css`, `btop/themes/matugen.theme`, and the rest. `ml4w-wallpaper` re-renders all of them on every wallpaper change.

**No matugen output is tracked under `home/`.** Stow folds at the directory level — `~/.config/waybar` is a symlink to `.stow/dotfiles/.config/waybar`, not a tree of per-file symlinks — so matugen writes into the generated `.stow/` tree and never touches the repo. Tracking a copy under `home/` therefore only ever produces a frozen snapshot that nothing reads. `apply.sh` copies the live palette into the tree it is about to rsync, since `rsync --delete` would otherwise wipe it on every apply.

Two consequences when adding a matugen output:
- Its directory has to exist in the stow tree, or `apply.sh` skips carrying the live copy across and `rsync --delete` wipes it on the next apply. `btop/themes/` and `ml4w/colors/` contain nothing but generated files, so they hold a `.gitkeep` to survive.
- A machine with no palette yet gets one from `ml4w/wallpapers/default.jpg` at the end of `apply.sh`. Missing outputs are fatal, not cosmetic: `hyprland.lua` does `require("colors")` and `hyprlock.conf` does `source = colors.conf`.

### Preserved files

Anything a program writes under a stow-folded directory lands in `.stow/`, not the repo, and the `rsync --delete` in `apply.sh` wipes it on the next apply.
`preserve_live_files` copies such a file out of `$HOME` back into the tree being rsynced.
It is fed the matugen outputs (see **Colors** above) and the `PRESERVE` list, which holds files a GUI owns: currently `.config/gtk-3.0/bookmarks`, the Nautilus sidebar.

Preserving and tracking are not exclusive, and `bookmarks` is both.
The live file wins over the tracked one, so `home/.config/gtk-3.0/bookmarks` only ever seeds a machine that has none, and edits made in Nautilus survive.
Committing a change to it therefore does nothing on a machine that already has the file — edit the sidebar there instead, and copy it into `home/` to move the default.
GTK parses each line as an absolute `file://` URI and expands nothing itself, so the tracked copy writes `$HOME` and `apply.sh` substitutes it while staging — the `EXPAND` list, which also carries the waybar theme stylesheet.
That makes the tracked copy unusable as-is: stowing `home/` by hand rather than through `apply.sh` produces a sidebar of dead entries.

The same directory-must-exist rule applies: a `PRESERVE` entry only survives if its parent directory is in the stow tree.

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
