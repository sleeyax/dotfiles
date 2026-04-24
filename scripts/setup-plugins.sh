#!/usr/bin/env bash
set -e

hyprpm update
hyprpm add https://github.com/hyprwm/hyprland-plugins || true
hyprpm enable hyprscrolling
hyprpm reload
