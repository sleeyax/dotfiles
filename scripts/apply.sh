#!/bin/bash
# Apply dotfiles: upstream base + common overrides + device-specific overrides
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(dirname "$SCRIPT_DIR")"

UPSTREAM="$DOTFILES_DIR/upstream"
COMMON="$DOTFILES_DIR/custom/common"

# Check for pacman (we only support Arch-based distro for now)
if ! command -v pacman &>/dev/null; then
  echo "Error: pacman not found"
  exit 1
fi

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
    sudo pacman -S --noconfirm stow
  fi

  # Run package setup
  "$SETUP_DIR/setup-arch.sh"

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

# Restore upstream before copying (clean slate)
git -C "$UPSTREAM" checkout -- dotfiles/

# Copy common overrides into upstream
cp -r "$COMMON/." "$UPSTREAM/dotfiles/"

# Copy device-specific overrides into upstream
cp -r "$DEVICE_DIR/." "$UPSTREAM/dotfiles/"

# Hide modifications from git
git -C "$UPSTREAM" diff --name-only | xargs -I {} git -C "$UPSTREAM" update-index --assume-unchanged {}
# Exclude untracked custom files from submodule
EXCLUDE="$(git -C "$UPSTREAM" rev-parse --git-dir)/info/exclude"
git -C "$UPSTREAM" status --porcelain | awk '/^\?\?/ {print $2}' > "$EXCLUDE"

# Stow the combined dotfiles
cd "$UPSTREAM" && stow -t "$HOME" --restow dotfiles

echo "Done! Configs applied for device: $DEVICE"

# Reload hyprland if running
if pgrep -x "Hyprland" > /dev/null; then
  echo "Reloading Hyprland..."
  hyprctl reload || true
fi
