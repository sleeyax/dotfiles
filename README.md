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
./scripts/setup-plugins.sh   # install Hyprland plugins (one-time, per device)
./scripts/apply.sh
```

This will:

1. Install Hyprland plugins via `hyprpm` (hyprscrolling)
2. Install ML4W from pinned upstream
3. Apply device-specific custom configs

Use `./scripts/apply.sh --force` to reinstall base. Re-run `setup-plugins.sh` after each Hyprland upgrade.

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

## Devices

| Device  | Hostname | Keyboard    | Monitor            |
| ------- | -------- | ----------- | ------------------ |
| Desktop | falcon   | QWERTY (us) | DP-5 3840x2160@144 |
| Laptop  | panda    | AZERTY (be) | eDP-1              |
