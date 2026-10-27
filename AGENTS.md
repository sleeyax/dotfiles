# AGENTS.md

This file provides guidance to AI agents when working with code in this repository.

## Overview

Personal Hyprland dotfiles for Arch Linux, originally based on [ML4W](https://github.com/mylinuxforwork/dotfiles) and vendored since. Manages configuration across three machines using GNU Stow: desktop "falcon", laptop "panda" and headless VPS "aardwolf".

## Key Commands

```bash
./scripts/apply.sh          # Auto-detect device by hostname, merge configs, deploy via stow
./scripts/apply.sh --force  # Reinstall all packages
./scripts/set-device.sh desktop  # Manually switch to desktop config
./scripts/set-device.sh laptop   # Manually switch to laptop config
./scripts/set-device.sh server   # Manually switch to server config
```

## Architecture

### Layered Override System

Configs are merged in order: **base → device-specific**, where the device layer overrides the base.

```
home/                           # The base tree, ours to edit; maps 1:1 to $HOME
devices/desktop/                # falcon-specific (QWERTY, 4K DP-5 @ 144Hz, scale 1.2)
devices/laptop/                 # panda-specific (AZERTY + QWERTY toggle, eDP-1, gestures)
devices/server/                 # aardwolf-specific (headless; shell only)
```

The `apply.sh` script copies `home/`, overlays device configs into `.stow/dotfiles/`, and runs `stow -t $HOME --restow dotfiles` to symlink everything into `$HOME`.

There is no "common" layer: shared customisations are edits to `home/` itself. A file only belongs in `devices/` if a machine genuinely needs different content.

`home/` is a Hyprland desktop, so a headless device takes only a slice of it — see **Headless devices** below.

### Packages

The lists are one package per line with `#` comments, grouped by subsystem. Every list is *appended* to the ones before it rather than overriding them — unlike the config tree, where a device file replaces the base file at the same path.

| List | Installed on | With |
| ---- | ------------ | ---- |
| `setup/packages.txt` | every Arch machine | `yay`/`paru` |
| `setup/packages.apt.txt` | every apt machine, i.e. aardwolf | `apt-get` |
| `setup/packages.graphical.txt` | every machine with `GRAPHICAL=1`, i.e. falcon and panda | `yay`/`paru` |
| `setup/packages.<device>.txt` | that device only | the device's manager |

The first two are the same list under two sets of names, and `PKG_MANAGER` (see **Package managers** below) picks which one a device reads; only one is ever in play. The split from `packages.graphical.txt` is the load-bearing one, and the question for a new package is which side of it the package falls on: anything that opens a window, draws on one, themes one or talks to a session daemon goes in `packages.graphical.txt`. `packages.<device>.txt` is for the narrower case of one machine wanting something the others shouldn't have; the default is the widest list the package works on.

They live in `setup/` and not `devices/<device>/` because `apply.sh` copies everything under `devices/<device>/` into the stow tree verbatim; a package list there would be symlinked into `$HOME`.

Whether to install is decided by hashing the lists in play into `$XDG_STATE_HOME/sleeyax-dotfiles/packages.sha256`. Adding a package to any of them therefore installs it on the next apply, with no flag needed; `--force` reinstalls regardless. The hash covers only the lists that device uses, so an edit to `packages.graphical.txt` doesn't churn the VPS.

On pacman, an apply then installs only what is missing: the list is filtered through `pacman -T` first, so an entry whose installed version is out of date is left alone rather than upgraded. Keeping the system current is a separate `pacman -Syu`. `--force` skips the filter and hands the whole list to the helper, which does upgrade. The apt path has no such filter, since `apt-get install` on a machine with a fresh index upgrades what it names.

### Package managers

`PKG_MANAGER` is a `setup/device.<device>.sh` knob defaulting to `pacman`, and `apply.sh` maps it to both a base list and the command that installs it. The check that the binary exists runs right after the device knobs are sourced rather than at the end, so a machine whose manager isn't there fails before anything has been rsynced or stowed.

Only aardwolf sets `apt`. Ubuntu is hard-coded for it rather than detected, because a second Ubuntu machine is not on the horizon and detection would be a guess dressed as a fact.

Adding a package to `packages.txt` therefore means adding it to `packages.apt.txt` too, or deciding it doesn't belong on a headless box. `packages.apt.txt` names in its header the three entries that have no counterpart — `pacman-contrib`, `libsecret`, `oh-my-posh-bin` — so the divergence is recorded in one place rather than rediscovered.

The last of those is the one with a consequence outside the list: `.config/ohmyposh` is still stowed on aardwolf, but oh-my-posh ships no apt package, so the prompt block in `home/.config/zshrc/20-customization` runs `oh-my-posh init` only when the binary is on `PATH`. `install_oh_my_posh` in `apply.sh` puts it there — see **Unpackaged dependencies** below.

### Unpackaged dependencies

Two things the shell config needs can't be had from a list on every distro — oh-my-zsh is packaged on neither, and oh-my-posh only on Arch — so `apply.sh` installs them itself, between the packages and the services.

`install_oh_my_zsh` clones oh-my-zsh, then clones the three plugins `20-customization` names that oh-my-zsh doesn't bundle: `zsh-autosuggestions`, `zsh-syntax-highlighting`, `fast-syntax-highlighting`. Cloning rather than running upstream's installer is deliberate — that installer moves `~/.zshrc` aside and writes its own, and ours is a stow symlink. A missing plugin is only a warning per new shell, which is easy to stop seeing, so the check covers each one rather than just the `~/.oh-my-zsh` directory.

`install_oh_my_posh` fetches the release binary to `~/.local/bin`, and only on an apt device. Arch has `oh-my-posh-bin` in `packages.txt`, so a missing binary there means that install failed — worth seeing, rather than papering over with a download that then shadows the package. It tests `~/.local/bin/oh-my-posh` as well as `PATH`, because `apply.sh` runs under bash and it's `00-init` that puts that directory on `PATH`, for zsh — and only upgrades the copy at that path, since one on `PATH` from anywhere else belongs to whatever put it there.

Being a download and not a package, no system upgrade will ever move it forward, so once it is installed the function runs `oh-my-posh upgrade` instead. That is the tool's own updater: silent, and exit 0, when it is already current. It is also the one bit of network a settled apply spends, which is why the failure is a notice rather than a failed apply — a machine that can't reach GitHub keeps the version it has.

Both run on every apply rather than behind the package stamp, since each costs a test and nothing else once satisfied — the same arrangement as `enable_services`, and what lets a half-provisioned machine heal itself. Neither is gated on `GRAPHICAL`: the prompt and the plugins are wanted on all three devices.

### Services

Installing a package is not the same as enabling its unit, and `apply.sh` enables the handful that have to be running before the session rather than on demand.
The list is the `SERVICES` array in `apply.sh` itself: with one entry, a `setup/services.txt` alongside the package lists would buy nothing.
`enable_services` skips whatever `systemctl is-enabled` already reports, so a normal apply never prompts for sudo. It doesn't run at all on a headless device, where none of these units is installed.

Only a unit whose *timing* matters belongs here.
`power-profiles-daemon` is the case that forced it: it ships D-Bus activated, waybar's power-profiles module is what triggers the activation, and that module segfaults when the call lands in the window where the display manager's greeter session is tearing its bus connections down.
The race is won on most boots and lost on a slow one, which makes it look like a change when nothing changed.

### Device Detection

`scripts/detect-device.sh` maps hostname to device name (`falcon` → desktop, `panda` → laptop, `aardwolf` → server). A manual override can be saved to `~/dotfiles/device` (gitignored). The fallback for an unknown hostname is `desktop`, which is the safe way round: a new machine gets too much rather than a shell with nothing in it.

### Headless devices

`setup/device.<device>.sh` is sourced by `apply.sh` and holds the knobs that aren't a package list. Only a device that differs from the graphical default needs one, and only `server` has one today:

```bash
GRAPHICAL=0
PKG_MANAGER=apt
STOW_PATHS=(.zshrc .config/zshrc .config/ohmyposh)
```

`GRAPHICAL=0` drops `packages.graphical.txt` from the install and skips every step in `apply.sh` that assumes a session: `enable_services`, `xdg-user-dirs-update`, seeding a matugen palette, and creating `~/.mydotfiles`. Each of those is a hard failure and not a cosmetic one on a machine without the packages — `matugen` isn't installed, and the `theme_pref=$(grep ... gtk-3.0/settings.ini)` above it would take `set -e` down on the missing file.

`STOW_PATHS` is an allowlist: with it set, the merged tree is reduced to exactly those paths before it is rsynced into `.stow/`. It names what to *keep*, so a new directory under `home/` has to be opted in here before it reaches the VPS — the opposite default from a droplist, and the right one for a machine that should have less. The filter runs after the device overlay, so a `devices/server/` file still wins at a kept path; a device file at a dropped path is silently discarded, which is why an unmatched entry warns.

`.config/btop` is deliberately not kept: the only local change to it is `color_theme = "matugen"`, naming a theme the wallpaper pipeline generates and a headless host never will.

`.bashrc` is not kept either, and it is the one path where the distro's copy beats ours. `home/.bashrc` is an Arch skeleton — two colour aliases, a `PS1`, and a `PATH` line `00-init` already sets for zsh — while Ubuntu ships a fuller one that fnm, cargo, pnpm and the `paseo.env` block have all appended to. Keeping it would trade live machine-local config for a worse file, and `stow` refuses the overwrite in any case, since a real file at a stow target is a conflict rather than something to adopt. bash is only aardwolf's login shell until `chsh` points at zsh; the zsh side is stowed in full.

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

The base copies of `input.lua`, `monitors.lua` and `hypridle.conf` never deploy: the graphical devices override them and the server stows no `hypr` at all. They are kept as the documented shape of a per-device file: adding another graphical device means copying one, not inventing it.

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
| 2 | `custom/claude-usage` | `waybar/scripts/claude-usage.sh fetch` |
| 3 | `custom/codex-usage` | `waybar/scripts/codex-usage.sh fetch` |
| 4 | `custom/kef` | `quickshell/KefApp/KefService.qml`, on any change the pill shows |
| 5 | `custom/backup` | `borgmatic/status.sh`, on every write to the backup status file |

`SIGUSR2` is different in kind, and nothing fires it.
Waybar answers it by tearing every bar down and rebuilding it, which frees the modules while their async DBus calls are still in flight; `power-profiles-daemon` then segfaults when its reply lands on the freed object, and `launch.sh` backgrounds waybar under no supervision, so the bar simply stays gone.
The wallpaper hook that used to send it now relaunches waybar through `launch.sh` instead — the same rebuild, in a process with no stale callbacks.
Anything wanting a whole-bar refresh does the same; a module that only needs its own output refreshed takes a signal from the table above.

`reload_style_on_change` is the one that costs nothing: waybar watches the stylesheet, and reloads the style provider alone without touching a module. It resolves an `@import` against its own config directories and never against the importing file, so an import it is meant to watch has to be an absolute path — see **Drawing with images** below.

`escape: true` escapes Pango markup, which is right for a module printing arbitrary text and wrong for one drawing with markup. A module that draws leaves it off and escapes its own interpolations instead — or, as the two usage scripts do, interpolates nothing but generated integers and fixed labels.

**Module state never goes under a stow-folded config dir.** `~/.config/waybar` and `~/.config/hypr` are symlinks into `.stow/dotfiles/`, which `apply.sh` runs `rsync -a --delete` over, so a cache written beside the script is destroyed on the next apply. Write to `${XDG_CACHE_HOME:-$HOME/.cache}` instead. (This is the general form of the rule in **Preserved files** below.)

`claude-usage.sh fetch` is the module's only source: it reads the OAuth token out of `$CLAUDE_CONFIG_DIR/.credentials.json` (`~/.claude` when that is unset) and asks `GET /api/oauth/usage`, which is where Claude Code itself gets these percentages.
Asking is the only way to have the numbers.
The `statusLine` command is the one place Claude Code hands `rate_limits` to a script, and a statusline only renders in the terminal client, so a session driven through the SDK (like T3 Code) yields none — which is why the statusline, kept in the promptfiles repo, prints a readout and feeds nothing.

Nothing else a session leaves behind carries a percentage either: the SDK's `rate_limit_event`, the `anthropic-ratelimit-unified-*` response headers and the CLI's startup `quota_check` all report a status and a reset time, while the transcripts under `~/.claude/projects/` and the `claude_code.*` OTel metrics report tokens.
`~/.claude.json` holds a `cachedUsageUtilization` snapshot of the right shape, but no SDK session refreshes it, which is the same gap again.

`codex-usage.sh` is the same module against OpenAI: it reads the access token out of `$CODEX_HOME/auth.json` (`~/.codex` when that is unset) and asks `GET https://chatgpt.com/backend-api/wham/usage`, which returns the windows Codex itself records.
It records them locally too — every rollout under `~/.codex/sessions/` carries a `rate_limits` object — but only for a session that ran here, so reading those would make the bar a log of this machine rather than a view of the account.

How many windows a Codex plan has is the plan's business: the response carries a `primary_window` and a `secondary_window` that may be null, and their `limit_window_seconds` is what names them.
So the module draws a ring per window present and derives each label, where `claude-usage.sh` knows its two windows by name.
The spacer count and the `background-position` offsets follow from that count, which is why its geometry constants are named rather than written into the CSS string.

Both scripts share the rest.
`render` starts a `fetch` in the background once the `last-fetch` marker is older than `REFRESH_INTERVAL`.
The marker records attempts and not successes, so a broken endpoint is asked no oftener than a working one.
Neither endpoint is documented, so a failure is expected rather than a bug to chase: the cache keeps the last numbers and the tooltip reports their age.

**Drawing with images.** Neither module has text beyond spaces: every `background-image` layer is painted over them. The first is the vendor mark — `waybar/claude.svg` or `waybar/openai.svg`, both tracked assets, recoloured and drawn at 18px against the rings' 16px so the mark reads as the label rather than another gauge. The rest are the usage rings. No font glyph fills continuously — the closest, `nf-md-circle_slice_1..8`, quantises to eighths — so an exact percentage has to be drawn.

Five things follow, and they are the price of the exact fill:
- **The script owns the colour.** An image cannot inherit the module's CSS `color:`, so each script resolves `on_surface`/`tertiary`/`error` out of `~/.config/waybar/colors.css` itself and writes the hex into the SVG. A wallpaper change rewrites that palette silently, so the colour is re-read every render and the rings catch up within one `interval`.
- **The script owns the declaration too, not just the images.** GTK caches the decoded image in the style provider and would keep painting it over rewritten bytes, so a redrawn ring has to arrive under a name GTK has never seen. Each script therefore names its rings after what they draw (`ring-<pct>-<hex>.svg`) and generates the whole `background-image` block into `$XDG_CACHE_HOME/<name>-usage/rings.css`, which `themes/ml4w-modern/default/style.css` `@import`s and waybar reloads on change. Nothing about the layers belongs in the theme's `style.css`, since a rule there would override the generated one.
- **Those imports are absolute, and the tracked copy is a placeholder.** Waybar resolves an `@import` against its own config directories rather than against the importing file, and only watches what it resolves. The tracked stylesheet carries `$XDG_CACHE_HOME`, which `apply.sh` expands while staging — the same arrangement as `bookmarks` under **Preserved files**, and unusable as-is if `home/` is stowed by hand. `launch.sh` runs both scripts before starting the bar, because waybar builds its watch list once from the imports that resolved at parse time.
- **The text holds the space open, not the padding.** A label's hit region follows its text, so anything sitting over CSS padding is unhoverable — with padding, only the glyph the module used to draw took hover, and the tooltip came with it. Neither module has horizontal padding at all: the script emits one non-breaking space per 9.6px at `font-size: 16px`, enough to cover the mark and its rings, and the images are painted over them at pixel offsets. The spaces are non-breaking because Pango may drop ordinary ones at an edge, and the `font-family` rule below is load-bearing for the same reason — their advance is the whole layout. Changing the font or its size means re-measuring the offsets.
- Anything hover-related on these modules must set `background-color`, never the `background` shorthand: the shorthand resets `background-image` and the rings vanish on hover.

### KEF panel

`home/.config/quickshell/KefApp/` is a Quickshell client for [kefw2ui](https://github.com/hilli/kefw2ui), whose `server/server.go` is the API contract.
`KefService.qml` owns the backend and the speaker state; the window, the tab views, the `kef` IPC target and the waybar pill all go through it.

**Lifecycle.** `KefService` starts `kefw2ui -bind 127.0.0.1 -port 18080` on first use and reuses whatever already answers on that port.
The backend and its `curl` event stream both run under `setpriv --pdeathsig TERM`, because Quickshell leaves its children running when it gets SIGTERM, which is how `ml4w-autostart` restarts it.
`waybar/scripts/kef.sh` reads the backend and never starts it.
It runs once and then only on signal 4, which `KefService` fires on every change it sees, so the pill is as fresh as the last time the panel was open and no fresher.
An `interval` here would ask the speaker all day, and the backend cannot tell that it has gone into standby by itself without its events, so a timer risks keeping it awake.

**No speaker events on falcon.** kefw2ui 0.0.3 registers the speaker's event queue with a GET, which firmware V26120 answers with 501; the same fields as a JSON POST work, so the fix belongs in go-kef-w2's `registerQueue`.
Until it ships, `/events` carries only the connect snapshot plus what the backend broadcasts itself (`playlists`, `reindex`), and `KefService` polls `/api/player` while the panel is open.
The polling keys off `speakerHealth`, so it stops once a fixed backend connects.

**Standby.** Only `/api/player` and `/api/speaker` answer from cache while the speaker sleeps; every other endpoint queries the speaker and wakes it.
The queue, play mode, browse and settings therefore load only after a fresh `/api/player` shows the speaker awake (`awakeStateStale`).
Playlists are backend files and safe to read at any time.

**Playlists.** `PUT /api/playlists/<id>` overwrites the description whenever it is left out, so every save sends the whole playlist.

**Testing.** Run the repo tree as its own instance with `qs -p home/.config/quickshell`, and drive it with `qs -p home/.config/quickshell ipc call kef …`; `status` returns the parsed state.
That instance reloads whenever a file under its config dir changes, and a reload stops the backend it started.
The panel's `HyprlandFocusGrab` closes it on any click outside, so take a screenshot within a few seconds of `open`.

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

### Backups

falcon and panda back `$HOME` up to a Hetzner Storage Box with borgmatic driving borg; the only script of our own is `scripts/setup-backups.sh`, which provisions a machine once.
The user-facing guide is [docs/backups.md](docs/backups.md), written for someone new to borg, and it is where a change in behaviour gets explained.

`home/.config/borgmatic/config.yaml` is one config for both workstations, so nothing in it may be machine-specific.
The repository is `ssh://storagebox/./borg`, where `storagebox` is a host alias each machine's untracked `~/.ssh/config` resolves to its own Storage Box sub-account.
That keeps the per-machine username out of the repo, and gives a manual `borg` or `ssh` the same name borgmatic uses.
aardwolf is out of scope: its `STOW_PATHS` never picks up `.config/borgmatic`, and the packages are in `packages.graphical.txt`.

**Borg 1.4 on both ends.** Hetzner serves borg 1.1, 1.2 and 1.4 and defaults to 1.2, and borg 2 is still in beta.
`remote_path: borg-1.4` picks the server side; an `authorized_keys` forced command ignores the client's remote path, so one has to name `borg-1.4 serve` itself.

**Encryption.** `repokey`: AES-256 with HMAC-SHA256, the key stored in the repository under the passphrase.
Both workstations have SHA hardware acceleration, so the blake2 variant buys nothing.
The passphrase is read with `secret-tool lookup service borgmatic repository storagebox`; that attribute pair is the contract with whatever stores it, so changing it strands every machine already set up.

**Setting a machine up.** `scripts/setup-backups.sh` creates the machine's sub-account, key, `storagebox` alias, keyring passphrase and repository, sets the box's snapshot plan and locks its main account down, and is run by hand with `HCLOUD_TOKEN` in the environment.
hcloud stays out of the package lists because nothing after setup needs it, and the token never goes through `hcloud context`, which would save it to disk.
Each step decides it is done by observing the result rather than keeping a record: the sub-account by name, the key by whether ssh gets past authentication (any exit but 255), the passphrase by a keyring search, the repository by borg's exit code from a `repo-list`, the snapshot plan and the main account's Samba and WebDAV by `storage-box describe`.
Showing the passphrase and key export is the one step with no observable result that is unsafe to repeat, so it alone leaves a marker in `$XDG_STATE_HOME/backup/`, holding the repository ID so a recreated repository is shown again.
Resetting the main account's password has no observable result either, but replacing one discarded password with another changes nothing, so it runs on every run; that also makes a rerun the way to lock the account again after its password was reset in the Console.

The script uploads `authorized_keys` itself rather than using Hetzner's `install-ssh-key`, which also adds an RFC4716 copy that port 22 honours without the forced command.
`--restrict-to-repository ./borg` is relative because where the sub-account's chroot puts its home is Hetzner's business; borg resolves both it and the client's `/./borg` against the login directory.
That `borg-1.4 serve` exists as a forced command on Hetzner is inferred, not documented, which is why the script checks the server version through the restricted key on every run.
Locally, a user-level `sshd` with `cd <dir> &&` in front of the forced command stands in for the chroot and exercises the restricted line with real borg; the password upload can only be tried against the real box.

**Restore mode.** `--restore` runs the same script on a machine that replaces a lost one under the same hostname: it finds the sub-account rather than creating it, asks for the passphrase rather than generating it, never creates a repository, and turns `backup.timer` off rather than on.
The timer stays off because a backup of a home that isn't restored yet would become the newest archive and prune a real one.
Everything else is shared, and that is what re-keys the sub-account: the new machine has no `~/.ssh/storagebox`, so a fresh key is generated and its upload replaces the lost machine's line in `authorized_keys`.

borgmatic exits 1 on any error, so `probe_repository` reads borg's own exit code out of its log: 13 for a missing repository, 52 for a wrong passphrase.
borg opens the repository before the key, so a probe with a random passphrase tells whether the repository exists without knowing the real one.
Normal mode probes that way before storing a new passphrase, and stops with a pointer to `--restore` on a machine whose hostname already has a repository, rather than storing a passphrase that can't open it.
A candidate passphrase reaches borgmatic as `BACKUP_PASSCOMMAND='printenv SETUP_PASSPHRASE'`, the same environment-only route as the askpass, and is stored only once it has opened the repository; restore mode overwrites a stored passphrase only after borg has rejected it.
The probe and the repository ID use `repo-list` rather than `repo-info`, which builds borg's chunk cache, and on a fresh machine that means reading every archive's index.

The guide's whole-machine extract leaves out `~/.ssh/storagebox*` and the `timers.target.wants/backup.timer` link.
The archive's key is the one restore mode just replaced, and a later run of the script would upload whatever key it finds, letting the lost disk back in.
The archive's link would enable the timer at the next login, undoing restore mode's while the extract may still be unfinished.

Both modes can run end to end without the box: a fake `$HOME` whose borgmatic config points at a local repository, with `hcloud`, `ssh`, `sftp`, `secret-tool`, `systemctl` and `getent` stubbed first on `PATH`.
`ssh -G` has to stay real, with `-F` pointing at the fake `~/.ssh/config`, since ssh reads the passwd home rather than `$HOME`.

**Snapshots and the main account.** Every key can delete its own archives, since each run prunes, so the box's automatic snapshots are the one copy a compromised machine can't touch: only the API makes or deletes them, and the token is deleted after setup.
The plan is box-wide — weekly, Sunday 00:00 UTC, keeping 10 — so both machines set the same one and the second finds it done.
The night from Saturday to Sunday is chosen to fall far from falcon's 19:00 runs and panda's working day, so a snapshot normally holds repositories at rest.
`hcloud -o json` prints Sunday as `day_of_week: 0` while the API stores `7` (its output conversion casts `time.Weekday` without the mapping its input side has), so the check accepts either rather than pinning a CLI bug.
The main account can reach both repositories, so the script turns its Samba and WebDAV off and discards its password, and nothing on a workstation can wipe the whole box; `update-access-settings` sends only the flags given, so its SSH, ZFS-folder and external-reachability settings are left as they are.
Snapshots are only visible to the main account, under `.zfs/snapshot`, which is why the guide's browsing steps re-key it temporarily and end with a rerun of the script.

**What goes in.** The source is `~` with `one_file_system`, so mounts inside it are skipped.
`home/.config/borgmatic/patterns` is the rsync exclusion list from the old external-drive script (`~/Scripts/exclude.txt`, untracked), translated to borg pattern syntax by the rules in its header, then extended with the caches and downloaded toolchains dry runs over falcon's and panda's `$HOME` turned up.
The price of `!` over `-` is that no `+` can re-include anything beneath an excluded folder, so a broad name like `**/build` or `**/Downloads` takes every folder of that name in `$HOME`.

`MEGAsync` is the one entry dropped in translation: MEGA propagates a deletion or corruption to every device, so it isn't a backup by itself.
Only its local trash, `MEGAsync/.debris`, stays out.
panda's MEGA folder holds the same files as falcon's, and borg deduplicates only within one repository, so panda leaves `~/MEGA` out entirely rather than store a second copy.
`exclude_caches` and `exclude_if_present: .nobackup` are the ways to leave a folder out without editing the list.

That is the one exclusion that differs by machine, and it lives in `patterns.device`, a second `patterns_from` entry that a device overrides under `devices/<device>/`.
The base copy is a header and nothing else, there so that every machine has the file `config.yaml` names.
An entry that matches nothing costs nothing, so an exclusion belongs in the shared list unless it would drop something another machine needs.

`borg_exit_codes` downgrades 105, a file borg can't read, from an error to a warning.
falcon's `$HOME` holds Docker database volumes inside projects, owned by container UIDs; a user's run can never read them, and an error would fail every run over them.
The price is that a file which turns unreadable later is skipped quietly too.

A `before: action` hook on `create` writes `pacman -Qqe` to `$XDG_STATE_HOME/backup/packages.txt`, so every archive says what a rebuilt machine should reinstall.
borgmatic interpolates `${VAR}` across the whole config at load time, hooks included, so a shell variable in a hook is written `\${VAR}` or without braces.
YAML reads a bare `~` as null, which is why the source is quoted.

**History and checks.** Keep 7 daily, 4 weekly and 6 monthly; every run prunes and compacts its own repository, so there is no append-only mode and no separate prune host.
`repository` and `archives` checks run every 2 weeks and `spot` every 3 months; `data` reads back the whole repository and so is never scheduled.
The spot check hashes with `xxh64sum`, which comes from `xxhash`, a borg dependency.
`retries: 3` with `retry_wait: 300` backs off linearly, retrying about 5, 15 and 30 minutes after the first failure — enough to outlast a router reboot.
A dropped connection can leave its lock on the box well after the client gave up: on panda's first backup the lock outlived a connection reset by more than 19 minutes and was gone within 28 without a `break-lock`, so the box's `borg serve` evidently lived on until the box noticed the connection was dead.
`lock_wait: 600` lets each try wait 10 minutes for the lock rather than borg's default of 1 second, which carries the retries past that window.
The price is that a lock held for real, such as a mounted archive on falcon, costs each try 10 minutes before it fails.

**What a run logs.** `statistics: quick` ends each run's journal entry with the new archive's sizes, and prune's with what it deleted; `quick` leaves out the repository-wide totals, which say nothing about the run.
`list_details` stays off: a line per added or modified file would bury the rest of the log, and `borg create` couldn't name deleted files anyway, since it only walks what is on disk.
`borgmatic/changes.sh` covers both on demand, with `borgmatic diff --content-only` between the two newest archives.
It isn't run per backup because a diff reads both archives' file lists from the box, the same cost that keeps `info` out of the status path.
`--content-only` drops files whose timestamps changed but whose contents didn't.

**Scheduling.** falcon backs up at 19:00, during dinner, and never while it could be in use; every choice in the next paragraph serves that.
`backup.timer` starts `backup.service` daily at 19:00 local time and is not `Persistent`, so a day the machine was off is skipped rather than caught up at boot.
A timer whose elapse passed during suspend fires on resume all the same, so the service's `ExecCondition=` runs `borgmatic/on-schedule.sh`, which lets a run start only until 19:10.
It judges the time it is given, the current time when given none, and that argument is how it is tested: `on-schedule.sh 19:09` exits 0, `on-schedule.sh 19:11` exits 1.
`ExecCondition=` reads exit 1 as a skip and 255 as a failure, and a condition is checked once, at start, so a run that started in time is never stopped by it.

panda is on a day or two a week, during working hours and rarely at 19:00, so it backs up once on each day it is used instead, through laptop overrides of the same two files.
Its `backup.timer` fires 10 minutes after the user manager starts, which is at login, and then hourly.
Its `on-schedule.sh` skips the run when `last_run` in the status file falls on the judged day, so one attempt a day gets through, and a failure waits for tomorrow rather than notifying every hour.
It also skips while any `borg` or `borgmatic` of the user's is running, since a backup by hand or a mounted archive holds the repository lock, and a timer run that failed on it would use up the day.
Both scripts take the same optional argument, a time in any form `date -d` reads, so either can be asked about a time other than now.
`backup.service` runs at `Nice=19` and `IOSchedulingClass=idle` on both machines, for panda's sake.
An hourly elapse that comes due during a long run fires again the moment the run ends, and the condition is what turns that into a skip.

`ConditionACPower=true` holds on a machine with no AC connectors at all, so it only ever skips panda on battery; a skipped hour writes nothing, so the next hour on AC still gets the day's attempt.
A skip by either condition leaves the unit inactive rather than failed, so `OnFailure=backup-failed.service`, a `notify-send`, fires only for a run that started and failed.

borgmatic runs beside a `systemd-inhibit --what=sleep --mode=block`, which `borgmatic/inhibit-sleep.sh` starts in the background before it `exec`s borgmatic.
borgmatic has to be the unit's main process: systemd sends a stop's SIGTERM to every process in the unit and kills whatever is left once the main process exits.
Were `systemd-inhibit` the main process, it would die on the first SIGTERM and take borgmatic's `fail` hook down with it, leaving a stopped run reading `running` with no `last_run`; `KillMode=mixed` only turns that into a SIGKILL.
Block mode refuses an unprivileged suspend outright: hypridle's `systemctl suspend` on panda gets "Operation denied due to active block inhibitor", and a manual one on falcon is refused until forced with `systemctl suspend -i` and an admin password.
hypridle tries once per idle period, so panda stays awake after a backup ends until it next goes idle.
The lid switch still suspends, because logind's `LidSwitchIgnoreInhibited=` defaults to yes and nothing in Hyprland takes the switch.
Shutdown is deliberately not inhibited; the run reads `failed` and the next one reuses what was uploaded.

The units are stowed from `home/.config/systemd/user/`, and `apply.sh` creates `~/.config/systemd/user` before stowing, because enabling a unit writes a `*.target.wants/` link beside the unit files and a folded directory would put that link in the stow tree for `rsync --delete` to wipe.
`apply.sh` also runs `systemctl --user daemon-reload`, and never enables `backup.timer`: `setup-backups.sh` does, as its last step, so a machine whose setup stopped partway never fails a backup every day.
systemd lists a symlinked unit file as `linked`, and `systemctl --user disable` deletes such a link along with the enable link; the next apply puts the unit file back, still disabled.

**The status file.** `$XDG_STATE_HOME/backup/status.json` is the contract between a run and whatever reports on it.
Anything that shows backup health reads this file and at most the timer's schedule or whether it is enabled, so it never reaches the Storage Box or the keyring.
`home/.config/borgmatic/status.sh` writes it from three hooks, replacing the whole file in one rename so a reader never sees half of one:

| Field | Value |
| ----- | ----- |
| `state` | `running`, `succeeded` or `failed` |
| `last_run` | Unix time the last run ended, whether it succeeded or failed |
| `last_success` | Unix time the last successful run ended; a failure leaves it alone |
| `added_bytes` | what the newest archive holds that no other archive does, measured at the end of that run |
| `archives` | how many archives the repository held at the end of that run |

Only `state` is always there: `last_run` is missing until a first run ends, the other three until a first success, and `added_bytes` and `archives` are null when that success couldn't be measured, or while it is still being measured.
A reader shows either as unknown rather than failing.

The hooks are `configuration`-level and filtered to `when: create`, so only a run that makes an archive writes the file, and `borgmatic repo-list` by hand never does.
borgmatic retries inside that level, so a run reads `running` across its retries and `failed` only once the last one has failed.
borgmatic runs the `fail` hook on SIGTERM too, so a backup stopped by a shutdown or `systemctl --user stop` reads `failed`; only a run killed outright, by SIGKILL or a power cut, leaves `running` behind until the next one starts.

The two numbers cost the run one more borgmatic call, made by the success hook after it has recorded the success.
That call is the only part of the status path that reaches the repository or the keyring, and it belongs to the run rather than to a reader.
Nothing cheaper has the size: `info` on the newest archive downloads and decrypts its whole file list, which on a full `$HOME` can add minutes to a run.
A failure, or a kill while it runs, leaves the success recorded and the numbers null, rather than failing a backup that worked.
`added_bytes` is borg's deduplicated size of the newest archive, read after the prune: a chunk it shared only with a pruned archive counts as its own, so the figure can slightly overstate what the run uploaded.

**The waybar pill.** `custom/backup` runs `waybar/scripts/backup.sh`, a reader of the status file that also asks systemd for the timer's next elapse.
It passes that elapse to `on-schedule.sh` and shows it only if the run would go ahead, and "tomorrow" otherwise, so the schedule's rules live in one script per machine; on falcon the 19:00 elapse always passes.
`status.sh` sends signal 5 after every write, so the pill follows a run as it starts and ends; the 60-second interval only ages the tooltip and lets `ok` turn `stale`.
`running` and `failed` describe the newest run, so they win over the age of the last success.
No status file reads `never`, dimmed rather than amber: a machine that was never set up has nothing to fix, and a set-up one settles it on its first run.
A status file jq can't parse reads `failed`, since the pill has no way left to tell the run's outcome.
A left click opens the journal at its end, with `--boot=all` because `journalctl -e` otherwise implies the current boot, which on falcon often holds no run.
A right click runs `changes.sh` in a terminal; unlike the rest of the pill it reaches the box and the keyring, which is acceptable for something that only runs when asked.
The guide's **Reading the waybar icon** section is where a change to the states gets explained.

The pill's `stale` and the staleness check below each have a threshold in days, and both live in `borgmatic/staleness`, which the two scripts source and a device overrides.
They are 3 and 7 by default, and 7 and 14 on panda, which is on a day or two a week and so goes a week without a backup as a matter of course.
That is a sourced file rather than an `Environment=` drop-in because the pill runs under waybar, out of systemd's reach.

**The staleness check.** `borgmatic/notify-if-stale.sh` sends a critical notification when the last success is more than `NOTIFY_STALE_DAYS` days old, for backups that stopped without ever failing: a timer turned off, a machine never on when its timer fires.
It judges `last_success` alone, so a `failed` or `running` state changes nothing; a failed run already has `backup-failed.service`, and a `running` left behind by a kill must not hide a gap.
A status file without `last_success`, or one jq can't parse, notifies too.
Without a status file, it notifies only while `backup.timer` is enabled, which is what tells a set-up machine from one that was never set up.
That also means a machine notifies at its first login after setup, before the first run has written the file.

`backup-stale.timer` is `WantedBy=` and `PartOf=graphical-session.target`, so it starts with each login and fires a minute later, once swaync has taken the notification name; nothing D-Bus activates it.
uwsm is what starts and stops that target, through `wayland-session@hyprland.desktop.target`, so the check depends on SDDM launching the uwsm Hyprland session rather than the plain one; `systemctl --user is-active graphical-session.target` tells which.
It fires daily at 12:00 as well, which is `OnCalendar=` rather than `OnUnitActiveSec=1d` because a monotonic timer stops counting during suspend.
`apply.sh` enables it on every graphical machine, unlike `backup.timer`, because it is silent on one that was never set up; a deliberate `disable` therefore lasts only until the next apply.
It starts the timer only inside a session, since a check fired from an SSH apply would find no notification daemon and fail unreported.
Test it by pointing `XDG_STATE_HOME` at a directory holding a handwritten `backup/status.json`; the guide's **When backups fail or go stale** section explains the notification.

**Testing against a throwaway repository.** Two environment variables override the config without editing it, and unlike a CLI flag they can be handed to a systemd user unit with `systemctl --user set-environment`:

| Variable | Replaces | Default |
| -------- | -------- | ------- |
| `BACKUP_REPOSITORY` | the repository path | `ssh://storagebox/./borg` |
| `BACKUP_PASSCOMMAND` | the passphrase command | the `secret-tool` lookup above |

```bash
mkdir -p ~/borg-test && touch ~/borg-test/.nobackup
export BACKUP_REPOSITORY=~/borg-test/repo BACKUP_PASSCOMMAND='echo test' XDG_STATE_HOME=~/borg-test/state
borgmatic repo-create --encryption repokey
borgmatic --retries 0 create --stats
borgmatic list --archive latest
```

Put the test repository in a `.nobackup` folder, or the run backs up its own repository; that also exercises the marker.
`XDG_STATE_HOME` keeps a test run's status file, and borgmatic's record of when each check last ran, away from the machine's real ones.
`--source-directories '["/some/dir"]'` swaps `~` for a small tree, for a test that needs a run to finish in seconds.
Never store a test passphrase under the real `secret-tool` attributes, where it would pass for the machine's real one.
Pass `--retries 0` to anything expected to fail, or it sits out the full half hour of backoff.

To test a run through `backup.service` itself — the inhibitor, `OnFailure=`, what the journal shows — put a runtime drop-in in `$XDG_RUNTIME_DIR/systemd/user/backup.service.d/` that empties `ExecCondition=`, sets the variables above with `Environment=`, and repeats `ExecStart=` with `--retries 0`, then `daemon-reload`.
A `BACKUP_PASSCOMMAND` that sleeps holds a run open long enough to watch it: before exiting 1, to try a suspend against the inhibitor and then fail the run; before printing the passphrase, to watch the waybar pill read `running`.
borgmatic splits the passcommand into words without a shell, so the sleep goes in a script of its own.
Delete the drop-in and reload again afterwards.

`borgmatic config validate` never interpolates environment variables, so it warns that `${BACKUP_REPOSITORY:-ssh://…}` is a deprecated scp-style path and shows it mangled.
A real run resolves the variable first and says nothing; the warning is harmless.

### Shell Configuration

Zsh configs in `home/.config/zshrc/` are numbered for load order (`00-init`, `20-customization`, `25-aliases`). Init sets up NVM, PATH (cargo, go), and `EDITOR=code`. Aliases include eza-based ls/ll/lt, hyprlock, nmtui, and ML4W app shortcuts.

`devices/server/.config/zshrc/26-server` is the one device layer in the numbering: it lands after `25-aliases` and undoes the parts of it that need a session, sets `EDITOR=nvim`, and puts `shutdown` back to the real command — on a VPS, an alias for `systemctl poweroff` is one typo away from the provider console.

`.zshrc` sources those in order and then `~/.zshrc_custom`, which is the only supported place for machine-local, uncommitted shell config. It has to sit in `$HOME`: `~/.config/zshrc` is a stow symlink into `.stow/`, so anything added under it is destroyed by the `rsync --delete` in `apply.sh`.

## Devices

| Device  | Hostname | Keyboard    | Monitor            | Idle: Lock/Off/Suspend |
|---------|----------|-------------|--------------------|------------------------|
| Desktop | falcon   | QWERTY (us) | DP-5 3840x2160@144 | 10m / 11m / never      |
| Laptop  | panda    | AZERTY (be) | eDP-1              | 10m / 15m / 30m        |
| Server  | aardwolf | -           | headless VPS       | n/a                    |
