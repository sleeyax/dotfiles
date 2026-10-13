#!/usr/bin/env bash
# Waybar module for backup health.
# Reads the status file the backup hooks write, whose fields and readers are the contract under Backups in AGENTS.md.

set -euo pipefail

STATUS="${XDG_STATE_HOME:-$HOME/.local/state}/backup/status.json"
source "$HOME/.config/borgmatic/staleness"

emit() {
    jq -cn --arg text "$1" --arg tooltip "$2"$'\n\n'"Click to open the log" --arg class "$3" '{text: $text, tooltip: $tooltip, class: $class}'
}

when() {
    date -d "@$1" '+%a %-d %b %H:%M'
}

next_run() {
    local next
    next=$(systemctl --user show backup.timer --property=NextElapseUSecRealtime --value --timestamp=unix 2>/dev/null) || true
    if [ -z "$next" ]; then
        echo "No backup is scheduled"
    elif "$HOME/.config/borgmatic/on-schedule.sh" "$next" 2>/dev/null; then
        echo "Next backup: $(when "${next#@}")"
    else
        # panda's timer fires hourly, but once the day's backup has ended, every elapse left today is skipped.
        echo "Next backup: tomorrow"
    fi
}

ago() {
    local seconds=$1 count unit
    if ((seconds < 60)); then
        echo "just now"
        return
    elif ((seconds < 3600)); then
        count=$((seconds / 60)) unit=minute
    elif ((seconds < 86400)); then
        count=$((seconds / 3600)) unit=hour
    else
        count=$((seconds / 86400)) unit=day
    fi
    ((count == 1)) || unit+=s
    echo "$count $unit ago"
}

state="" last_success="" added_bytes="" archives=""
if [ -e "$STATUS" ]; then
    if ! fields=$(jq -r '@sh "state=\(.state | strings // "") last_success=\(.last_success | numbers // "") added_bytes=\(.added_bytes | numbers // "") archives=\(.archives | numbers // "")"' "$STATUS" 2>/dev/null); then
        emit "󰧠" "$STATUS can't be read" failed
        exit 0
    fi
    eval "$fields"
fi

now=$(date +%s)
if [ "$state" = running ]; then
    headline="Backing up now" icon="󰅧" class=running
elif [ "$state" = failed ]; then
    headline="The last backup failed" icon="󰧠" class=failed
elif [ -z "$last_success" ]; then
    headline="Never backed up" icon="󰅤" class=never
elif ((now - last_success >= PILL_STALE_DAYS * 86400)); then
    headline="No backup in the last $PILL_STALE_DAYS days" icon="󰧠" class=stale
else
    headline="Backups are up to date" icon="󰅠" class=ok
fi

tooltip="$headline"
if [ -n "$last_success" ]; then
    tooltip+=$'\n'"Last backup: $(when "$last_success") ($(ago $((now - last_success))))"
    added=unknown
    [ -z "$added_bytes" ] || added=$(numfmt --to=si --suffix=B --round=nearest "$added_bytes")
    tooltip+=$'\n'"Added: $added"
    tooltip+=$'\n'"Archives: ${archives:-unknown}"
elif [ "$class" != never ]; then
    tooltip+=$'\n'"No backup has succeeded yet"
fi
tooltip+=$'\n'"$(next_run)"

emit "$icon" "$tooltip" "$class"
