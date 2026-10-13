#!/usr/bin/env bash
# Lets one backup a day through: backup.timer tries every hour, and once a run has ended that day, succeeded or failed, the rest are skipped.
# A failure therefore waits for tomorrow rather than notifying every hour; a backup by hand is the way to retry sooner.
# backup.service runs it as ExecCondition=, where exit 1 skips the run and 255 fails it.
#
#   on-schedule.sh [TIME]   judge TIME, in any form date -d reads, rather than now
set -euo pipefail

STATUS="${XDG_STATE_HOME:-$HOME/.local/state}/backup/status.json"

if ! day=$(date -d "${1:-now}" +%F 2>/dev/null); then
    echo "usage: ${0##*/} [TIME]" >&2
    exit 255
fi
midnight=$(date -d "$day" +%s)

# A backup by hand, or a mounted archive, holds the repository lock, and a run started now would fail on it and use up the day.
if pgrep -u "$USER" -x 'borg|borgmatic' >/dev/null; then
    echo "borg is already running; skipping this hour." >&2
    exit 1
fi

# Without a readable status file there is no run to have ended today.
last_run=$(jq -r '.last_run | numbers // 0' "$STATUS" 2>/dev/null) || last_run=0
if ((last_run >= midnight)); then
    echo "A backup already ran on $day; skipping until tomorrow." >&2
    exit 1
fi
