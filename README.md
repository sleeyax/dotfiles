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
1. Install ML4W base from pinned upstream (if not already installed)
2. Apply device-specific custom configs

Use `./scripts/apply.sh --force` to reinstall base.

## Usage

Pull new changes and update the submodule to the latest pinned commit:

```bash
$ git pull
$ git submodule update
```

Then run the apply script again.

### Other scripts

**Auto-detect device** (by hostname):
```bash
./scripts/apply.sh
```

**Manual device switch**:
```bash
./scripts/set-device.sh desktop  # or laptop
```

## Update upstream

```bash
cd upstream
git fetch --tags
git checkout <new-tag>
cd ..
git add upstream
git commit -m "update upstream to <tag>"
```

## Devices

| Device | Hostname | Keyboard | Monitor |
|--------|----------|----------|---------|
| Desktop | falcon | QWERTY (us) | DP-5 3840x2160@144 |
| Laptop | panda | AZERTY (be) | eDP-1 |
