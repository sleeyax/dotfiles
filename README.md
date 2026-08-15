# Sleeyax's Dotfiles

Personal Hyprland dotfiles.

Based on [ML4W](https://github.com/mylinuxforwork/dotfiles) **2.14.1** (`f974938`, 2026-07-09), vendored and maintained independently since.
Upstream's own `version.json` reports 2.12.3 at that tag; the tag is authoritative, and that file is not vendored here.

## Structure

```
├── home/               # The base tree. Maps 1:1 to $HOME
├── devices/
│   ├── desktop/        # falcon-specific (QWERTY, 4K monitor)
│   └── laptop/         # panda-specific (AZERTY, gestures)
├── setup/
│   └── packages.txt    # Packages installed by apply.sh
└── scripts/            # Apply/switch scripts
```

`home/` is deployed as-is, then `devices/$DEVICE/` is overlaid on top of it, so a device file always wins over the base file at the same path.

Packages are the exception: `devices/$DEVICE/packages.txt` is *added* to `setup/packages.txt` rather than replacing it, so it only exists to give a device something the other one shouldn't have.

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

The base commit above is the merge base for porting a feature out of a newer release. The recipe is in [AGENTS.md](AGENTS.md#integrating-a-feature-from-a-newer-ml4w); it is plain `git diff` and `git show` against an `ml4w` remote, so there is no wrapper script to keep working.

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

## Devices

| Device  | Hostname | Keyboard    | Monitor            |
| ------- | -------- | ----------- | ------------------ |
| Desktop | falcon   | QWERTY (us) | DP-5 3840x2160@144 |
| Laptop  | panda    | AZERTY (be) | eDP-1              |
