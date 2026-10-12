#!/usr/bin/env bash
# Sends a desktop notification when the last successful backup is more than a week old; backup-stale.timer runs it at login and daily.
# Reads the status file the backup hooks write, whose fields and readers are the contract under Backups in AGENTS.md.
set -euo pipefail

STATUS="${XDG_STATE_HOME:-$HOME/.local/state}/backup/status.json"
# The waybar icon turns amber after 3 days; a notification is for a gap that has outlasted that.
STALE_DAYS=7

notify() {
    notify-send --urgency=critical --app-name=Backup --icon=dialog-warning "$1" "$2"
}

if [ ! -e "$STATUS" ]; then
    # The first run writes the file, so without one only an enabled timer says this machine was meant to have backed up.
    systemctl --user is-enabled --quiet backup.timer || exit 0
    notify "Never backed up" "No backup has run on this machine yet."
    exit 0
fi

if ! last_success=$(jq -er '.last_success | numbers // ""' "$STATUS" 2>/dev/null); then
    notify "Backup status unreadable" "$STATUS can't be read, so there is no telling when the last backup succeeded."
    exit 0
fi

if [ -z "$last_success" ]; then
    notify "Never backed up" "No backup has succeeded on this machine yet."
    exit 0
fi

age=$(($(date +%s) - last_success))
if ((age > STALE_DAYS * 86400)); then
    notify "No backup in $((age / 86400)) days" "The last one that succeeded was on $(date -d "@$last_success" '+%a %-d %b')."
fi
