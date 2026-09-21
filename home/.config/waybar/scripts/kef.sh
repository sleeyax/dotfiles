#!/usr/bin/env bash
# Waybar module for the KEF speaker panel.
# Reads the kefw2ui backend that Quickshell starts on demand, and never starts it itself, so the bar does not wake a backend nobody asked for.

set -euo pipefail

# A machine without kefw2ui prints nothing, and hide-empty-text drops the module.
command -v kefw2ui >/dev/null 2>&1 || exit 0

port=18080

emit() {
    jq -cn --arg text "$1" --arg tooltip "$2" --arg class "$3" '{text: $text, tooltip: $tooltip, class: $class}'
}

if ! player=$(curl -sf --max-time 1 "http://127.0.0.1:$port/api/player"); then
    emit "󰓃" "KEF speaker"$'\n'"Click to open the panel" "offline"
    exit 0
fi

source=$(jq -r '.source' <<<"$player")
if [ "$source" = "standby" ]; then
    emit "󰓃" "KEF speaker is in standby" "standby"
    exit 0
fi

volume=$(jq -r '.volume' <<<"$player")
muted=$(jq -r '.muted' <<<"$player")
title=$(jq -r '.title // ""' <<<"$player")
artist=$(jq -r '.artist // ""' <<<"$player")
state=$(jq -r '.state' <<<"$player")

if [ "$muted" = "true" ]; then
    text="󰓄  muted"
    class="muted"
else
    text="󰓃  ${volume}%"
    class="$state"
fi

tooltip="${title:-Nothing playing}"
[ -n "$artist" ] && tooltip+=$'\n'"$artist"
tooltip+=$'\n'"${source} · volume ${volume}%"$'\n\n'"Left: panel · Middle: play/pause · Right: mute · Scroll: volume"

emit "$text" "$tooltip" "$class"
