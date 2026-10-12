#!/usr/bin/env bash
# Lets a backup start only in the ten minutes after backup.timer's 19:00, so the timer catching up on resume from suspend skips the day rather than backing up while the machine is in use.
# backup.service runs it as ExecCondition=, where exit 1 skips the run and 255 fails it.
#
#   on-schedule.sh [HH:MM]   judge HH:MM rather than the current time
set -euo pipefail

START=19:00
CUTOFF=19:10

minutes() {
    [[ $1 =~ ^([01][0-9]|2[0-3]):([0-5][0-9])$ ]] || return 1
    echo $((10#${BASH_REMATCH[1]} * 60 + 10#${BASH_REMATCH[2]}))
}

now=${1:-$(date +%H:%M)}
if ! at=$(minutes "$now"); then
    echo "usage: ${0##*/} [HH:MM]" >&2
    exit 255
fi

if ((at < $(minutes $START) || at > $(minutes $CUTOFF))); then
    echo "It is $now, outside $START-$CUTOFF; skipping today's backup." >&2
    exit 1
fi
