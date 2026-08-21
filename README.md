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
│   ├── packages.txt    # Packages installed by apply.sh
│   └── packages.desktop.txt  # ...plus these, on falcon only
└── scripts/            # Apply/switch scripts
```

`home/` is deployed as-is, then `devices/$DEVICE/` is overlaid on top of it, so a device file always wins over the base file at the same path.

Packages work differently: `setup/packages.$DEVICE.txt` is *added* to `setup/packages.txt` rather than replacing it, so it only exists to give a device something the other one shouldn't have.

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

## Nautilus extensions

[copy-path.py](home/.local/share/nautilus-python/extensions/copy-path.py) adds a *Copy Path* entry to the right-click menu, for the selection or for the folder being viewed, and puts the absolute paths on the clipboard one per line.

Nautilus loads extensions once at startup, so run `nautilus -q` after an apply to pick up a change.

## Coding agent usage

Two waybar pills next to the update counter show how much of each coding agent's quota is gone: a vendor mark, then a ring per rate limit window. Each ring fills clockwise from 12 o'clock to its exact percentage, and the rings turn amber past 75% and red past 90%. Hover either for the breakdown — used and left, when each window resets and how far off that is, and whether the first window is being burned faster or slower than the clock.

### Claude Code

The Claude pill has two rings: the rolling 5-hour session first, the 7-day second. Click to open the usage dashboard on claude.ai.

[claude.svg](home/.config/waybar/claude.svg) is the Claude mark from [Simple Icons](https://simpleicons.org), recoloured to Claude orange.

[claude-usage.sh](home/.config/waybar/scripts/claude-usage.sh) asks Anthropic for the numbers: it reads the OAuth token Claude Code keeps in `~/.claude/.credentials.json`, pulls the two windows off the account, and caches them under `~/.cache/claude-usage/`. Waybar re-runs the script every 30 seconds and it fetches at most every five minutes. Nothing has to be running for the pill to be right — no session, no particular client. ([statusline.sh](home/.claude/statusline.sh) still draws the model, branch and context readout inside Claude Code; it used to feed the pill and no longer does.)

### Codex

The Codex pill draws a ring per window the plan actually has — one on a Plus plan, whose single limit is weekly; two where a shorter window exists as well. Each ring's label comes from the window length the account reports, so the pill neither invents a window nor hides one. The tooltip adds a credits line when the account has any. Click to open the usage page on chatgpt.com.

[openai.svg](home/.config/waybar/openai.svg) is the OpenAI mark, recoloured white to read against the dark bar.

[codex-usage.sh](home/.config/waybar/scripts/codex-usage.sh) works the same way, reading the token Codex keeps in `~/.codex/auth.json` and caching under `~/.cache/codex-usage/`. Codex does write the same figures into every session rollout under `~/.codex/sessions/`, but only for sessions that ran on this machine, which is the wrong question.

### Both

- A pill hides itself until its first fetch lands, and stays hidden on a plan that has no rate limits to report.
- It reports the account, not the machine, so sessions on the web, the other device or in the cloud move the rings too. A window whose reset time has passed reads 0% again, so the display is right after a rollover even if no session has run since.
- Both endpoints are the ones the agents themselves get these numbers from, and neither vendor documents them. When one fails the last numbers stay on the bar and the tooltip's age line is what gives it away; run the script with `fetch` by hand to see why.

## Devices

| Device  | Hostname | Keyboard    | Monitor            |
| ------- | -------- | ----------- | ------------------ |
| Desktop | falcon   | QWERTY (us) | DP-5 3840x2160@144 |
| Laptop  | panda    | AZERTY (be) | eDP-1              |
