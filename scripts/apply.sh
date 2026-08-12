#!/bin/bash
# Apply dotfiles: base tree + device-specific overrides
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(dirname "$SCRIPT_DIR")"

BASE="$DOTFILES_DIR/home"
STOW_DIR="$DOTFILES_DIR/.stow"

PACKAGES_FILE="$DOTFILES_DIR/setup/packages.txt"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/sleeyax-dotfiles"
PACKAGES_STAMP="$STATE_DIR/packages.sha256"

# shellcheck source=../ml4w-base.env
source "$DOTFILES_DIR/ml4w-base.env"

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

DEVICE_DIR="$DOTFILES_DIR/devices/$DEVICE"

if [ ! -d "$DEVICE_DIR" ]; then
  echo "Error: Device directory not found: $DEVICE_DIR"
  exit 1
fi

# Installs the ML4W settings app the way its Makefile does, without running its setup.sh (which curl|bashes and pulls an unpinned HEAD).
install_settings_app() {
  local tmp lib_dir colors
  lib_dir="$HOME/.local/share/ml4w-dotfiles-settings"
  tmp=$(mktemp -d)

  git init -q "$tmp"
  git -C "$tmp" remote add origin "$ML4W_SETTINGS_REPO"
  git -C "$tmp" fetch -q --depth 1 origin "$ML4W_SETTINGS_COMMIT"
  git -C "$tmp" checkout -q FETCH_HEAD

  mkdir -p "$HOME/.local/bin" "$lib_dir"
  install -m 755 "$tmp/bin/ml4w-dotfiles-settings" "$HOME/.local/bin/"

  # colors/colors.json ships as a seed but is a live matugen output_path; overwriting it would reset the palette until the next wallpaper change.
  colors="$lib_dir/colors/colors.json"
  if [ -f "$colors" ]; then
    rm -f "$tmp/lib/colors/colors.json"
  fi
  cp -r "$tmp"/lib/. "$lib_dir/"

  rm -rf "$tmp"
}

install_dependencies() {
  if command -v yay &>/dev/null; then
    AUR_HELPER=yay
  elif command -v paru &>/dev/null; then
    AUR_HELPER=paru
  else
    echo "Error: no AUR helper found. Install yay or paru first:"
    echo "  sudo pacman -S --needed base-devel git"
    echo "  git clone https://aur.archlinux.org/yay-bin.git && (cd yay-bin && makepkg -si)"
    exit 1
  fi

  # awww declares Provides/Replaces on swww, so pacman does the swap itself and --noconfirm accepts it.
  # A different provider means the swap isn't the expected one.
  swww_provider=$(pacman -Qq swww 2>/dev/null || true)
  if [ -n "$swww_provider" ] && [ "$swww_provider" != "awww" ]; then
    echo "Notice: 'swww' resolves to '$swww_provider'; installing awww will replace it."
  fi

  echo "Installing packages with $AUR_HELPER..."
  mapfile -t PKGS < <(sed 's/#.*//' "$PACKAGES_FILE" | grep -vE '^\s*$' | tr -d '[:blank:]')
  "$AUR_HELPER" -S --needed --noconfirm "${PKGS[@]}"

  install_settings_app

  xdg-user-dirs-update

  mkdir -p "$STATE_DIR"
  sha256sum "$PACKAGES_FILE" | cut -d' ' -f1 > "$PACKAGES_STAMP"
}

# Parse flags
FORCE=0
for arg in "$@"; do
  case "$arg" in
    --force) FORCE=1 ;;
    *) echo "Unknown flag: $arg"; exit 1 ;;
  esac
done

# Hashing the package list rather than setting a boolean means adding a package is enough to trigger an install on the next apply.
WANT_HASH=$(sha256sum "$PACKAGES_FILE" | cut -d' ' -f1)
if [ "$FORCE" == "1" ] || [ ! -f "$PACKAGES_STAMP" ] || [ "$(cat "$PACKAGES_STAMP")" != "$WANT_HASH" ]; then
  install_dependencies
else
  echo "Packages unchanged since last install, skipping..."
  echo "(Run with --force to reinstall)"
fi

echo "Applying dotfiles for device: $DEVICE"

# Build merged dotfiles in temp dir, then sync into .stow in-place
# (avoids breaking symlinks in $HOME which causes screen flicker)
STOW_NEW=$(mktemp -d)
trap 'rm -rf "$STOW_NEW"' EXIT # Cleans up the temp dir if the script exits early for whatever reason
cp -r "$BASE" "$STOW_NEW/dotfiles"
cp -r "$DEVICE_DIR/." "$STOW_NEW/dotfiles/"

# Carry the live matugen palette across, so re-applying doesn't clobber it.
# Nothing under home/ is a matugen output: stow folds at the directory level, so
# matugen writes into the stow tree rather than the repo, and rsync --delete below
# would drop those files on every apply if they weren't preserved here.
# Two cases to untangle:
#   1. $HOME path resolves into the stow tree (stow symlink, possibly
#      folded at a parent dir): copy the live content into STOW_NEW.
#   2. $HOME has a real file that isn't stow-managed: drop it from
#      STOW_NEW so `stow --restow` doesn't conflict with it.
MATUGEN_CFG="$STOW_NEW/dotfiles/.config/matugen/config.toml"
if [ -f "$MATUGEN_CFG" ]; then
  STOW_REAL=$(realpath "$STOW_DIR" 2>/dev/null || echo "$STOW_DIR")
  while IFS= read -r rel; do
    [ -f "$HOME/$rel" ] || continue
    [ -d "$STOW_NEW/dotfiles/$(dirname "$rel")" ] || continue
    resolved=$(realpath "$HOME/$rel")
    case "$resolved" in
      "$STOW_REAL"/*) cp "$resolved" "$STOW_NEW/dotfiles/$rel" ;;
      *)              rm -f "$STOW_NEW/dotfiles/$rel" ;;
    esac
  done < <(grep -oE "output_path = ['\"]~/[^'\"]+['\"]" "$MATUGEN_CFG" | sed -E "s/.*~\/([^'\"]+).*/\1/")
fi

mkdir -p "$STOW_DIR"
rsync -a --delete "$STOW_NEW/" "$STOW_DIR/"
rm -rf "$STOW_NEW"

# Stow the combined dotfiles
cd "$STOW_DIR" && stow -t "$HOME" --restow dotfiles

# A machine that has never set a wallpaper has never run matugen, so it has no palette at all.
# That is fatal rather than ugly: hypr/colors.lua is require()d and hyprlock.conf sources colors.conf.
# Mirrors run_matugen in ml4w-wallpaper, including how it picks the mode.
if [ ! -f "$HOME/.config/hypr/colors.lua" ]; then
  echo "No palette found, generating one from the default wallpaper..."
  theme_pref=$(grep -E '^gtk-application-prefer-dark-theme=' "$HOME/.config/gtk-3.0/settings.ini" | awk -F'=' '{print $2}')
  mode="light"
  [ "$theme_pref" = "1" ] && mode="dark"
  matugen image "$HOME/.config/ml4w/wallpapers/default.jpg" --source-color-index 0 -m "$mode" || true
fi

# ~/.mydotfiles is the ML4W installer's project store, which this repo never creates because it deploys with stow instead.
# conf/autostart.lua still redirects ml4w-autostart's stdout into it, and a failed redirect silently skips the whole autostart (quickshell, nm-applet, wallpaper theming).
mkdir -p "$HOME/.mydotfiles"

echo "Done! Configs applied for device: $DEVICE"

# Reload hyprland if running
if pgrep -x "Hyprland" > /dev/null; then
  echo "Reloading Hyprland..."
  hyprctl reload || true
fi
