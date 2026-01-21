#!/bin/bash
# Apply dotfiles: upstream base + common overrides + device-specific overrides
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(dirname "$SCRIPT_DIR")"

UPSTREAM="$DOTFILES_DIR/upstream"
COMMON="$DOTFILES_DIR/custom/common"
ML4W_DIR="$HOME/.ml4w/dotfiles"

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

install_base() {
  echo "Installing ML4W base from pinned upstream..."

  # Create ml4w directory
  mkdir -p "$HOME/.ml4w"

  # Copy upstream to ml4w directory (remove old if exists)
  if [ -d "$ML4W_DIR" ]; then
    rm -rf "$ML4W_DIR"
  fi
  cp -r "$UPSTREAM" "$ML4W_DIR"

  # Detect distro and run setup
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    case "$ID" in
      arch|endeavouros|manjaro)
        echo "Detected Arch-based distro"
        cd "$ML4W_DIR/bin" && ./ml4w-hyprland-setup -m install && ./ml4w-hyprland-setup -p arch
        ;;
      fedora)
        echo "Detected Fedora"
        cd "$ML4W_DIR/bin" && ./ml4w-hyprland-setup -m install && ./ml4w-hyprland-setup -p fedora
        ;;
      opensuse*)
        echo "Detected openSUSE"
        cd "$ML4W_DIR/bin" && ./ml4w-hyprland-setup -m install && ./ml4w-hyprland-setup -p opensuse
        ;;
      *)
        echo "Error: Unsupported distro: $ID"
        exit 1
        ;;
    esac
  else
    echo "Error: Cannot detect distro"
    exit 1
  fi

  cd "$SCRIPT_DIR"
}

install_base

echo "Applying dotfiles for device: $DEVICE"

# Create target directories
mkdir -p ~/.config/hypr/conf
mkdir -p ~/.config/waybar

# --- Symlink common configs ---
echo "Linking common configs..."

# custom.conf (hyprland)
ln -sf "$COMMON/.config/hypr/conf/custom.conf" ~/.config/hypr/conf/custom.conf

# --- Symlink device-specific configs ---
echo "Linking device-specific configs ($DEVICE)..."

# device.conf (monitor, input overrides)
ln -sf "$DEVICE_DIR/.config/hypr/conf/device.conf" ~/.config/hypr/conf/device.conf

# keyboard.conf
if [ -f "$DEVICE_DIR/.config/hypr/conf/keyboard.conf" ]; then
  ln -sf "$DEVICE_DIR/.config/hypr/conf/keyboard.conf" ~/.config/hypr/conf/keyboard.conf
fi

# layout.conf
if [ -f "$DEVICE_DIR/.config/hypr/conf/layout.conf" ]; then
  ln -sf "$DEVICE_DIR/.config/hypr/conf/layout.conf" ~/.config/hypr/conf/layout.conf
fi

# hypridle.conf
if [ -f "$DEVICE_DIR/.config/hypr/hypridle.conf" ]; then
  ln -sf "$DEVICE_DIR/.config/hypr/hypridle.conf" ~/.config/hypr/hypridle.conf
fi

# waybar modules.json (if exists)
if [ -f "$DEVICE_DIR/.config/waybar/modules.json" ]; then
  ln -sf "$DEVICE_DIR/.config/waybar/modules.json" ~/.config/waybar/modules.json
fi

echo "Done! Configs applied for device: $DEVICE"

# Reload hyprland if running
if pgrep -x "Hyprland" > /dev/null; then
  echo "Reloading Hyprland..."
  hyprctl reload || true
fi
