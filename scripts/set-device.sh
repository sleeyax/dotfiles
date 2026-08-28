#!/bin/bash
# Manual device switch
# Usage: ./set-device.sh <device>

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(dirname "$SCRIPT_DIR")"

if [ -z "$1" ]; then
  echo "Usage: $0 <device>"
  # Listed from devices/ so a new device needs no edit here.
  echo "Available devices: $(cd "$DOTFILES_DIR/devices" && echo */ | tr -d '/' )"
  exit 1
fi

if [ ! -d "$DOTFILES_DIR/devices/$1" ]; then
  echo "Error: Device '$1' not found in devices/"
  exit 1
fi

echo "$1" > "$DOTFILES_DIR/device"
echo "Device set to: $1"
