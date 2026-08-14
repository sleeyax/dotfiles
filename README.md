# Sleeyax's Dotfiles

Personal Hyprland dotfiles.

Based on [ML4W](https://github.com/mylinuxforwork/dotfiles) **2.14.1** (`f974938`, 2026-07-09), vendored and maintained independently since.
ML4W's own `version.json` reports 2.12.3 at that tag; the tag is authoritative.

## Structure

```
├── home/               # The base tree. Maps 1:1 to $HOME
├── devices/
│   ├── desktop/        # falcon-specific (QWERTY, 4K monitor)
│   └── laptop/         # panda-specific (AZERTY, gestures)
├── setup/
│   └── packages.txt    # Packages installed by apply.sh
└── scripts/            # Apply/switch/upstream scripts
```

`home/` is deployed as-is, then `devices/$DEVICE/` is overlaid on top of it, so a device file always wins over the base file at the same path.

## Install

```bash
git clone https://github.com/sleeyax/dotfiles.git ~/dotfiles
cd ~/dotfiles
./scripts/apply.sh
```

This will:

1. Install everything in [setup/packages.txt](setup/packages.txt)
2. Merge the base tree with your device's configs and deploy them with stow

Packages are installed when the list changes, so adding an entry is enough to get it installed on the next apply.
Use `./scripts/apply.sh --force` to reinstall regardless.

### Local shell config

The zsh setup lives in [home/.config/zshrc/](home/.config/zshrc/) and is the same on every machine.
For anything you don't want committed, put it in `~/.zshrc_custom`; it is sourced last, so it overrides everything in the repo.

Don't add files under `~/.config/zshrc/` directly — that path is a stow symlink into the generated tree, and the next `apply.sh` deletes anything the repo didn't put there.

## Upstream (ML4W)

The tree under `home/` came from ML4W and is now ours to edit; there is no submodule and no merge to keep up with.
ML4W is still available as a git remote, so individual features can be pulled from newer releases on demand.

[ml4w-base.env](ml4w-base.env) records which upstream commit `home/` is based on.
[scripts/ml4w.sh](scripts/ml4w.sh) queries that upstream and ports changes out of it:

```bash
./scripts/ml4w.sh sync                     # fetch ML4W (creates the remote on first run)
./scripts/ml4w.sh tags                     # list upstream releases
./scripts/ml4w.sh diff base 2.15 .config/waybar  # what changed upstream
./scripts/ml4w.sh log base..2.15 [path]    # commits behind that diff
./scripts/ml4w.sh show 2.15 <path>         # print upstream's copy of a file
./scripts/ml4w.sh status                   # what we changed, base vs home/
./scripts/ml4w.sh take 2.15 <path>         # overwrite home/<path> with upstream's
./scripts/ml4w.sh port 2.15 <path>         # 3-way merge upstream's change into ours
```

Upstream's tags are fetched into `refs/ml4w-tags/*` rather than `refs/tags/*`, so they never show up in `git tag` or get pushed.

### Ported from later versions

Nothing yet — `home/` is still 2.14.1 throughout.

| Date | ML4W version | Paths | What and why |
| ---- | ------------ | ----- | ------------ |

## Other scripts

**Auto-detect device** (by hostname):

```bash
./scripts/apply.sh
```

**Manual device switch**:

```bash
./scripts/set-device.sh desktop  # or laptop
```

## Web apps

Install a website as a Chromium app that keeps its own cookies, logins and extensions, separate from your personal browser:

```bash
./scripts/install-webapp.py add Linear https://linear.app/
./scripts/install-webapp.py list
./scripts/install-webapp.py remove linear [--purge]
```

Each app gets its own Chromium user-data directory at `~/.config/chromium-<slug>` (mode `0700`), beside Chromium's own `~/.config/chromium`. That is a whole separate data tree, not just another profile inside your browser, so the app sees none of your Google session, history or extensions. The profile holds live logins, so it stays out of this repo — run the command once per device.

The app itself is installed from the site's web manifest, so the launcher entry gets the real name and icons and opens in a standalone window, with no tab strip or address bar. Verify isolation from inside the app window: `chrome://version` should report a Profile Path of `~/.config/chromium-<slug>/Default`.

Close the app's window before reinstalling or removing it: a second Chromium on the same profile hands off to the running one instead of doing the work.

Two things to know:

- The install is driven over Chromium's DevTools pipe, using the experimental `PWA` domain. If a future Chromium drops it, install by hand (⋮ → *Cast, save, and share* → *Install page as app…*, from a browser started with `chromium --user-data-dir=~/.config/chromium-<slug>`) and then run `./scripts/install-webapp.py fix-class <slug>`.
- Chromium writes `StartupWMClass=crx_<id>`, which no window ever reports: an app window's Wayland app id is the entry's own basename, `chrome-<id>-Default`. The script corrects it, so taskbars and Hyprland rules match. Chromium rewrites the entry when an app updates, undoing the fix; `fix-class <slug>` puts it back. Use `hyprctl clients` to read the class for a window rule.

Note that [chromium-flags.conf](home/.config/chromium-flags.conf) applies to every Chromium instance, web apps included — Arch's launcher reads it regardless of `--user-data-dir`.

## VS Code Claude credentials

VS Code's built-in Claude agent takes its credentials from the environment or from `~/.claude/settings.json`; there is no VS Code setting for it. To keep the token out of both this repo and the global environment, [`home/.local/bin/code`](home/.local/bin/code) wraps `code`, sources `~/.config/claude/env` and execs `/usr/bin/code`.

Create the file per device (it is never tracked here):

```bash
mkdir -p ~/.config/claude
printf 'CLAUDE_CODE_OAUTH_TOKEN=%s\n' "$(claude setup-token)" > ~/.config/claude/env
chmod 600 ~/.config/claude/env
```

`ANTHROPIC_API_KEY` works there too, as does any other variable — the file is sourced with `set -a`, so plain `KEY=value` lines are exported.

Every launch path resolves to the wrapper: `~/.local/bin` comes first in the shell's `PATH`, and `custom.lua` prepends it to Hyprland's `PATH` so keybinds and the app launcher (`Exec=code %F`) hit it as well. Quit all VS Code windows after changing the file — a running instance handles new `code` invocations itself, so it keeps the environment it started with.

## Devices

| Device  | Hostname | Keyboard    | Monitor            |
| ------- | -------- | ----------- | ------------------ |
| Desktop | falcon   | QWERTY (us) | DP-5 3840x2160@144 |
| Laptop  | panda    | AZERTY (be) | eDP-1              |
