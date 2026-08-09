# Sleeyax's Dotfiles

Personal Hyprland dotfiles based on [ML4W](https://github.com/mylinuxforwork/dotfiles).

## Structure

```
├── upstream/           # ML4W dotfiles (git submodule, don't edit)
├── custom/
│   ├── common/         # Shared configs (all devices)
│   └── devices/
│       ├── desktop/    # falcon-specific (QWERTY, 4K monitor)
│       └── laptop/     # panda-specific (AZERTY, gestures)
└── scripts/            # Apply/switch scripts
```

## Install

```bash
git clone --recurse-submodules https://github.com/sleeyax/dotfiles.git ~/dotfiles
cd ~/dotfiles
./scripts/apply.sh
```

This will:

1. Install ML4W from pinned upstream
2. Apply device-specific custom configs

Use `./scripts/apply.sh --force` to reinstall base.

## Update (consumer)

If you are using the dotfiles from this repository, pull new changes and update the submodule to the latest pinned commit:

```bash
$ git pull
$ git submodule update
```

Then run the apply script again.

## Update (contributor)

If you want to update the upstream ML4W dotfiles, use the update script:

```bash
./scripts/update.sh <tag>
```

Example: `./scripts/update.sh 2.10.0`

### Other scripts

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

Note that [chromium-flags.conf](custom/common/.config/chromium-flags.conf) applies to every Chromium instance, web apps included — Arch's launcher reads it regardless of `--user-data-dir`.

## Devices

| Device  | Hostname | Keyboard    | Monitor            |
| ------- | -------- | ----------- | ------------------ |
| Desktop | falcon   | QWERTY (us) | DP-5 3840x2160@144 |
| Laptop  | panda    | AZERTY (be) | eDP-1              |
