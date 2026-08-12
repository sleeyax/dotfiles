#!/usr/bin/env bash

hyprctl dispatch workspaceopt allfloat

# Notifications
source "$HOME/.config/ml4w/scripts/ml4w-notification-handler"

notify_user \
        --a "System" \
        --m "Windows on this workspace toggled to floating/tiling"
