#!/usr/bin/env bash
# Lets a backup start only in the ten minutes after backup.timer's 19:00, so the timer catching up on resume from suspend skips the day rather than backing up while the machine is in use.
# backup.service runs it as ExecCondition=, where exit 1 skips the run and 255 fails it.
#
#   on-schedule.sh [TIME]   judge TIME, in any form date -d reads, rather than now
set -euo pipefail

START=19:00
CUTOFF=19:10

minutes() {
    echo $((10#${1%:*} * 60 + 10#${1#*:}))
}

if ! now=$(date -d "${1:-now}" +%H:%M 2>/dev/null); then
    echo "usage: ${0##*/} [TIME]" >&2
    exit 255
fi
at=$(minutes "$now")

if ((at < $(minutes $START) || at > $(minutes $CUTOFF))); then
    echo "It is $now, outside $START-$CUTOFF; skipping today's backup." >&2
    exit 1
fi
