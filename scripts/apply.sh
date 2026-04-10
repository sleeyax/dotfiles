#!/bin/bash
# Apply dotfiles: upstream base + common overrides + device-specific overrides
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(dirname "$SCRIPT_DIR")"

UPSTREAM="$DOTFILES_DIR/upstream"
COMMON="$DOTFILES_DIR/custom/common"
STOW_DIR="$DOTFILES_DIR/.stow"

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

install_dependencies() {
  echo "Installing ML4W dependencies from pinned upstream..."

  SETUP_DIR="$UPSTREAM/setup"
  # post-arch.sh sources helper scripts via $repo_path
  export repo_path="$UPSTREAM"

  # Install stow if needed
  if ! command -v stow &>/dev/null; then
    echo "Installing stow..."
    sudo pacman -S --noconfirm stow
  fi

  # Preflight: AUR helper install, swww removal
  bash "$SETUP_DIR/preflight-arch.sh"

  # Pick AUR helper (preflight guarantees one exists)
  if command -v yay &>/dev/null; then
    AUR_HELPER=yay
  else
    AUR_HELPER=paru
  fi

  # Install package dependencies
  mapfile -t PKGS < <(grep -vE '^\s*(#|$)' "$SETUP_DIR/dependencies/packages" "$SETUP_DIR/dependencies/packages-arch" | awk -F: '{print $NF}')
  "$AUR_HELPER" -S --needed --noconfirm "${PKGS[@]}"

  # Post: oh-my-posh, ML4W settings app, cursors/fonts/icons, xdg dirs
  bash "$SETUP_DIR/post-arch.sh"

  # Mark as installed
  mkdir -p "$HOME/.ml4w"
  touch "$HOME/.ml4w/.installed"
}

# Force reinstall if requested
if [ "$1" == "--force" ]; then
  install_dependencies
# Check if base install needed
elif [ ! -f "$HOME/.ml4w/.installed" ]; then
  install_dependencies
else
  echo "Dependencies should already be installed, skipping..."
  echo "(Run with --force to reinstall)"
fi

echo "Applying dotfiles for device: $DEVICE"

# Build merged dotfiles in temp dir, then sync into .stow in-place
# (avoids breaking symlinks in $HOME which causes screen flicker)
STOW_NEW=$(mktemp -d)
trap 'rm -rf "$STOW_NEW"' EXIT # Cleans up the temp dir if the script exits early for whatever reason
cp -r "$UPSTREAM/dotfiles" "$STOW_NEW/dotfiles"
cp -r "$COMMON/." "$STOW_NEW/dotfiles/"
cp -r "$DEVICE_DIR/." "$STOW_NEW/dotfiles/"

mkdir -p "$STOW_DIR"
rsync -a --delete "$STOW_NEW/" "$STOW_DIR/"
rm -rf "$STOW_NEW"

# Stow the combined dotfiles
cd "$STOW_DIR" && stow -t "$HOME" --restow dotfiles

echo "Done! Configs applied for device: $DEVICE"

# Reload hyprland if running
if pgrep -x "Hyprland" > /dev/null; then
  echo "Reloading Hyprland..."
  hyprctl reload || true
fi
