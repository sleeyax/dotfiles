#!/bin/bash
# Apply dotfiles: base tree + device-specific overrides
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(dirname "$SCRIPT_DIR")"

BASE="$DOTFILES_DIR/home"
STOW_DIR="$DOTFILES_DIR/.stow"

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/sleeyax-dotfiles"
PACKAGES_STAMP="$STATE_DIR/packages.sha256"

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

# Per-device knobs. Only a device that isn't a graphical workstation needs a file; the defaults below are what the others want.
# Like the package lists, they live in setup/ rather than devices/, because everything under devices/ is copied into the stow tree verbatim and would land in $HOME.
GRAPHICAL=1        # 0 drops the graphical package list and every step below that assumes a session
PKG_MANAGER=pacman # the distro's package manager, which also picks which base list can name packages it knows
STOW_PATHS=()      # non-empty means stow only these paths out of the merged tree
DEVICE_CONF="$DOTFILES_DIR/setup/device.$DEVICE.sh"
if [ -f "$DEVICE_CONF" ]; then
  source "$DEVICE_CONF"
fi

# Package names don't survive a change of distro, so the base list belongs to the package manager rather than to the fleet.
case "$PKG_MANAGER" in
  pacman) PACKAGES_FILE="$DOTFILES_DIR/setup/packages.txt";     PKG_BINARY=pacman ;;
  apt)    PACKAGES_FILE="$DOTFILES_DIR/setup/packages.apt.txt"; PKG_BINARY=apt-get ;;
  *) echo "Error: unknown PKG_MANAGER '$PKG_MANAGER'"; exit 1 ;;
esac

# Fail here rather than after the tree has already been rsynced and stowed.
if ! command -v "$PKG_BINARY" &>/dev/null; then
  echo "Error: $PKG_BINARY not found"
  exit 1
fi

# The graphical and device lists are both additive: a device without either installs exactly the base list.
PACKAGES_FILES=("$PACKAGES_FILE")
if [ "$GRAPHICAL" == "1" ]; then
  PACKAGES_FILES+=("$DOTFILES_DIR/setup/packages.graphical.txt")
fi
if [ -f "$DOTFILES_DIR/setup/packages.$DEVICE.txt" ]; then
  PACKAGES_FILES+=("$DOTFILES_DIR/setup/packages.$DEVICE.txt")
fi

packages_hash() {
  cat "${PACKAGES_FILES[@]}" | sha256sum | cut -d' ' -f1
}

install_pacman_packages() {
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
  "$AUR_HELPER" -S --needed --noconfirm "${PKGS[@]}"
}

install_apt_packages() {
  echo "Installing packages with apt..."
  sudo apt-get update
  sudo apt-get install -y "${PKGS[@]}"
}

install_dependencies() {
  mapfile -t PKGS < <(sed 's/#.*//' "${PACKAGES_FILES[@]}" | grep -vE '^\s*$' | tr -d '[:blank:]')

  case "$PKG_MANAGER" in
    pacman) install_pacman_packages ;;
    apt)    install_apt_packages ;;
  esac

  # xdg-user-dirs ships with the session; a headless device has neither the
  # package nor anything that would read ~/Desktop.
  if [ "$GRAPHICAL" == "1" ]; then
    xdg-user-dirs-update
  fi

  mkdir -p "$STATE_DIR"
  packages_hash > "$PACKAGES_STAMP"
}

# Parse flags
FORCE=0
for arg in "$@"; do
  case "$arg" in
    --force) FORCE=1 ;;
    *) echo "Unknown flag: $arg"; exit 1 ;;
  esac
done

# Hashing the package lists rather than setting a boolean means adding a package is enough to trigger an install on the next apply.
WANT_HASH=$(packages_hash)
if [ "$FORCE" == "1" ] || [ ! -f "$PACKAGES_STAMP" ] || [ "$(cat "$PACKAGES_STAMP")" != "$WANT_HASH" ]; then
  install_dependencies
else
  echo "Packages unchanged since last install, skipping..."
  echo "(Run with --force to reinstall)"
fi

# Not everything the configs need is a package. Both checks below cost a test and
# nothing else on a machine that already has the thing, so they run on every
# apply rather than behind the package stamp above — the same arrangement as
# enable_services, and what makes a half-provisioned machine heal itself.

OMZ_DIR="$HOME/.oh-my-zsh" # must match the ZSH export in .config/zshrc/00-init

# None of these is an Arch or Ubuntu package, so no list above can name them.
OMZ_PLUGINS=(
  "zsh-autosuggestions      https://github.com/zsh-users/zsh-autosuggestions.git"
  "zsh-syntax-highlighting  https://github.com/zsh-users/zsh-syntax-highlighting.git"
  "fast-syntax-highlighting https://github.com/zdharma-continuum/fast-syntax-highlighting.git"
)

install_oh_my_zsh() {
  local entry name url dest

  # Upstream's installer is a curl|sh that also moves ~/.zshrc aside to write its
  # own. Ours is a stow symlink, so the clone the installer wraps is the part we want.
  if [ ! -d "$OMZ_DIR" ]; then
    echo "Installing oh-my-zsh..."
    git clone --depth=1 https://github.com/ohmyzsh/ohmyzsh.git "$OMZ_DIR"
  fi

  # 20-customization names these in plugins=(), and oh-my-zsh bundles none of
  # them. A missing one only warns, once per new shell, which is easy to stop seeing.
  for entry in "${OMZ_PLUGINS[@]}"; do
    read -r name url <<< "$entry"
    dest="$OMZ_DIR/custom/plugins/$name"
    if [ -d "$dest" ]; then
      continue
    fi
    echo "Installing oh-my-zsh plugin: $name"
    git clone --depth=1 "$url" "$dest"
  done
}

POSH_BIN="$HOME/.local/bin/oh-my-posh" # on PATH via the .local/bin export in 00-init

install_oh_my_posh() {
  local arch

  # packages.txt carries oh-my-posh-bin from the AUR, so a missing binary on an
  # Arch device means that install failed — worth seeing, rather than papering
  # over with a download that then shadows the package. apt has nothing at all,
  # which is why the prompt block in 00-init is guarded on the binary.
  if [ "$PKG_MANAGER" != "apt" ]; then
    return 0
  fi
  # A copy on PATH that isn't the one we drop belongs to whatever put it there,
  # and isn't this function's to upgrade or replace. Testing the install path
  # separately because apply.sh runs under bash, and it is 00-init that puts
  # ~/.local/bin on PATH, for zsh.
  if [ ! -x "$POSH_BIN" ] && command -v oh-my-posh &>/dev/null; then
    return 0
  fi

  # Being a download rather than a package, nothing in an upgrade of the system
  # will ever move this forward, so the apply that would have skipped it is the
  # one chance to. `upgrade` prints nothing and exits 0 when it is already
  # current, which is the settled case and the only network an apply spends
  # here; a machine that can't reach GitHub keeps what it has rather than
  # failing the apply over a prompt.
  if [ -x "$POSH_BIN" ]; then
    if ! "$POSH_BIN" upgrade; then
      echo "Notice: could not check for an oh-my-posh update; keeping the installed version"
    fi
    return 0
  fi

  case "$(uname -m)" in
    x86_64)  arch=amd64 ;;
    aarch64) arch=arm64 ;;
    *) echo "Notice: no oh-my-posh release for $(uname -m); the prompt stays off"; return 0 ;;
  esac

  # Fetching the release binary is the whole install; upstream's script only
  # picks the asset and drops it on PATH. From here on `upgrade` above keeps it
  # current, so this branch is the first apply on a machine and nothing after.
  echo "Installing oh-my-posh..."
  mkdir -p "$(dirname "$POSH_BIN")"
  curl -fsSL -o "$POSH_BIN" \
    "https://github.com/JanDeDobbeleer/oh-my-posh/releases/latest/download/posh-linux-$arch"
  chmod +x "$POSH_BIN"
}

install_oh_my_zsh
install_oh_my_posh

# power-profiles-daemon ships D-Bus activated, so it only starts once a client asks for it, and waybar is that client.
# Its power-profiles module segfaults when the activation lands in the window where the greeter session's bus connections are still going away.
# Enabling the unit means the name is already taken by the time the bar starts.
SERVICES=(power-profiles-daemon.service)

enable_services() {
  local pending=()
  for svc in "${SERVICES[@]}"; do
    systemctl is-enabled --quiet "$svc" 2>/dev/null || pending+=("$svc")
  done

  if [ ${#pending[@]} -gt 0 ]; then
    echo "Enabling system services: ${pending[*]}"
    sudo systemctl enable --now "${pending[@]}"
  fi
}

# Every unit here belongs to the session, so a headless device has none of them installed.
if [ "$GRAPHICAL" == "1" ]; then
  enable_services
fi

echo "Applying dotfiles for device: $DEVICE"

# Build merged dotfiles in temp dir, then sync into .stow in-place
# (avoids breaking symlinks in $HOME which causes screen flicker)
STOW_NEW=$(mktemp -d)
trap 'rm -rf "$STOW_NEW"' EXIT # Cleans up the temp dir if the script exits early for whatever reason
cp -r "$BASE" "$STOW_NEW/dotfiles"
cp -r "$DEVICE_DIR/." "$STOW_NEW/dotfiles/"

# A device with STOW_PATHS keeps only the paths it names; most of home/ is a
# desktop and means nothing without one. Filtering here, after the overlay
# rather than before it, keeps the usual precedence at a path that is kept.
if [ ${#STOW_PATHS[@]} -gt 0 ]; then
  KEPT=$(mktemp -d)
  for rel in "${STOW_PATHS[@]}"; do
    if [ ! -e "$STOW_NEW/dotfiles/$rel" ]; then
      echo "Warning: STOW_PATHS names '$rel', which is not in the merged tree"
      continue
    fi
    mkdir -p "$KEPT/dotfiles/$(dirname "$rel")"
    cp -r "$STOW_NEW/dotfiles/$rel" "$KEPT/dotfiles/$rel"
  done
  rm -rf "$STOW_NEW/dotfiles"
  mv "$KEPT/dotfiles" "$STOW_NEW/dotfiles"
  rmdir "$KEPT"
fi

# Carry live, untracked files across, so re-applying doesn't clobber them.
# Stow folds at the directory level, so a program writing to ~/.config/<dir>/<file>
# writes into the stow tree rather than the repo, and rsync --delete below would
# drop the file on every apply if it weren't preserved here.
# Two cases to untangle:
#   1. $HOME path resolves into the stow tree (stow symlink, possibly
#      folded at a parent dir): copy the live content into STOW_NEW.
#   2. $HOME has a real file that isn't stow-managed: drop it from
#      STOW_NEW so `stow --restow` doesn't conflict with it.
STOW_REAL=$(realpath "$STOW_DIR" 2>/dev/null || echo "$STOW_DIR")
preserve_live_files() {
  while IFS= read -r rel; do
    [ -f "$HOME/$rel" ] || continue
    [ -d "$STOW_NEW/dotfiles/$(dirname "$rel")" ] || continue
    resolved=$(realpath "$HOME/$rel")
    case "$resolved" in
      "$STOW_REAL"/*) cp "$resolved" "$STOW_NEW/dotfiles/$rel" ;;
      *)              rm -f "$STOW_NEW/dotfiles/$rel" ;;
    esac
  done
}

# Nothing under home/ is a matugen output; the palette only ever exists in the stow tree.
MATUGEN_CFG="$STOW_NEW/dotfiles/.config/matugen/config.toml"
if [ -f "$MATUGEN_CFG" ]; then
  grep -oE "output_path = ['\"]~/[^'\"]+['\"]" "$MATUGEN_CFG" \
    | sed -E "s/.*~\/([^'\"]+).*/\1/" \
    | preserve_live_files
fi

# Files that need an absolute path where nothing on the reading side expands one, so the tracked copy carries a placeholder for us to fill in.
EXPAND=(
  .config/gtk-3.0/bookmarks                           # GTK parses every bookmark as an absolute file:// URI
  .config/waybar/themes/ml4w-modern/default/style.css # waybar only watches an @import it can resolve, and it resolves nothing relative to the importing file
)
for f in "${EXPAND[@]}"; do
  [ -f "$STOW_NEW/dotfiles/$f" ] || continue
  sed -i -e "s|\$XDG_CACHE_HOME|${XDG_CACHE_HOME:-$HOME/.cache}|g" -e "s|\$HOME|$HOME|g" "$STOW_NEW/dotfiles/$f"
done

# Files a GUI owns. A tracked copy under home/ is only a seed for a machine that has none, since the live file wins here.
PRESERVE=(
  .config/gtk-3.0/bookmarks # Nautilus sidebar (GTK4 reads this path too)
)
printf '%s\n' "${PRESERVE[@]}" | preserve_live_files

mkdir -p "$STOW_DIR"
rsync -a --delete "$STOW_NEW/" "$STOW_DIR/"
rm -rf "$STOW_NEW"

# Stow the combined dotfiles
cd "$STOW_DIR" && stow -t "$HOME" --restow dotfiles

# A machine that has never set a wallpaper has never run matugen, so it has no palette at all.
# That is fatal rather than ugly: hypr/colors.lua is require()d and hyprlock.conf sources colors.conf.
# Mirrors run_matugen in ml4w-wallpaper, including how it picks the mode.
if [ "$GRAPHICAL" == "1" ] && [ ! -f "$HOME/.config/hypr/colors.lua" ]; then
  echo "No palette found, generating one from the default wallpaper..."
  theme_pref=$(grep -E '^gtk-application-prefer-dark-theme=' "$HOME/.config/gtk-3.0/settings.ini" | awk -F'=' '{print $2}')
  mode="light"
  [ "$theme_pref" = "1" ] && mode="dark"
  matugen image "$HOME/.config/ml4w/wallpapers/default.jpg" --source-color-index 0 -m "$mode" || true
fi

# ~/.mydotfiles is the ML4W installer's project store, which this repo never creates because it deploys with stow instead.
# conf/autostart.lua still redirects ml4w-autostart's stdout into it, and a failed redirect silently skips the whole autostart (quickshell, nm-applet, wallpaper theming).
if [ "$GRAPHICAL" == "1" ]; then
  mkdir -p "$HOME/.mydotfiles"
fi

echo "Done! Configs applied for device: $DEVICE"

# Reload hyprland if running
if pgrep -x "Hyprland" > /dev/null; then
  echo "Reloading Hyprland..."
  hyprctl reload || true
fi
