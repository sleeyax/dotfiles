#!/bin/bash
# Apply dotfiles: upstream base + common overrides + device-specific overrides
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(dirname "$SCRIPT_DIR")"

UPSTREAM="$DOTFILES_DIR/upstream"
COMMON="$DOTFILES_DIR/custom/common"

# Determine device (manual override or auto-detect)
if [ -f "$DOTFILES_DIR/device" ]; then
  DEVICE=$(cat "$DOTFILES_DIR/device")
else
  DEVICE=$("$SCRIPT_DIR/detect-device.sh")
fi

DEVICE_DIR="$DOTFILES_DIR/custom/devices/$DEVICE"

if [ ! -d "$DEVICE_DIR" ]; then
  echo "Error: Device directory not found: $DEVICE_DIR"
  exit 1
fi

# --- Install ML4W base if needed ---
install_base() {
  echo "Installing ML4W base from pinned upstream..."

  SETUP_DIR="$UPSTREAM/setup"

  # Install stow if needed
  if ! command -v stow &>/dev/null; then
    echo "Installing stow..."
    if command -v pacman &>/dev/null; then
      sudo pacman -S --noconfirm stow
    elif command -v dnf &>/dev/null; then
      sudo dnf install -y stow
    elif command -v zypper &>/dev/null; then
      sudo zypper install -y stow
    fi
  fi

  # Run package setup
  if command -v pacman &>/dev/null; then
    echo "Detected Arch-based distro"
    "$SETUP_DIR/setup-arch.sh"
  elif command -v dnf &>/dev/null; then
    echo "Detected Fedora"
    "$SETUP_DIR/setup-fedora.sh"
  elif command -v zypper &>/dev/null; then
    echo "Detected openSUSE"
    "$SETUP_DIR/setup-opensuse.sh"
  else
    echo "Error: No supported package manager found"
    exit 1
  fi

  # Install dotfiles via stow
  echo "Installing dotfiles..."
  cd "$UPSTREAM" && stow -t "$HOME" dotfiles

  # Mark as installed
  mkdir -p "$HOME/.ml4w"
  touch "$HOME/.ml4w/.installed"

  cd "$SCRIPT_DIR"
}

# Force reinstall if requested
if [ "$1" == "--force" ]; then
  install_base
# Check if base install needed
elif [ ! -f "$HOME/.ml4w/.installed" ]; then
  install_base
else
  echo "ML4W base already installed, skipping..."
  echo "(Run with --force to reinstall)"
fi

echo "Applying dotfiles for device: $DEVICE"

# --- Stow common configs (override upstream) ---
echo "Stowing common configs..."
stow -d "$DOTFILES_DIR/custom" -t "$HOME" --adopt --override='.*' --restow common

# --- Stow device-specific configs (override upstream + common) ---
echo "Stowing device-specific configs ($DEVICE)..."
stow -d "$DOTFILES_DIR/custom/devices" -t "$HOME" --adopt --override='.*' --restow "$DEVICE"

echo "Done! Configs applied for device: $DEVICE"

# Reload hyprland if running
if pgrep -x "Hyprland" > /dev/null; then
  echo "Reloading Hyprland..."
  hyprctl reload || true
fi
