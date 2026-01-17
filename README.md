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
# Clone repo with submodule
git clone --recurse-submodules https://github.com/sleeyax/dotfiles.git ~/dotfiles
cd ~/dotfiles

# Install ML4W base (pinned version)
./upstream/setup.sh

# Apply custom configs
./scripts/apply.sh
```

## Usage

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
git commit -m "chore: update upstream to <tag>"
```

## Devices

| Device | Hostname | Keyboard | Monitor |
|--------|----------|----------|---------|
| Desktop | falcon | QWERTY (us) | DP-5 3840x2160@144 |
| Laptop | panda | AZERTY (be) | eDP-1 |
