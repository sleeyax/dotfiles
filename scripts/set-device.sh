#!/bin/bash
# Manual device switch
# Usage: ./set-device.sh laptop|desktop

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(dirname "$SCRIPT_DIR")"

if [ -z "$1" ]; then
  echo "Usage: $0 <device>"
  echo "Available devices: laptop, desktop"
  exit 1
fi

if [ ! -d "$DOTFILES_DIR/custom/devices/$1" ]; then
  echo "Error: Device '$1' not found in custom/devices/"
  exit 1
fi

echo "$1" > "$DOTFILES_DIR/device"
echo "Device set to: $1"
