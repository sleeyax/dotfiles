#!/usr/bin/env bash
# Records each backup run in the status file; borgmatic's hooks in config.yaml call it.
# The file's fields, and what may read it, are the contract under Backups in AGENTS.md.
#
#   status.sh start            a run is starting
#   status.sh succeed CONFIG   the run CONFIG drove succeeded
#   status.sh fail             the run failed after every retry, or was stopped before it finished
set -euo pipefail

STATUS="${XDG_STATE_HOME:-$HOME/.local/state}/backup/status.json"

update() {
    mkdir -p "${STATUS%/*}"
    local previous tmp
    previous=$(jq -c . "$STATUS" 2>/dev/null) || previous='{}'
    tmp=$(mktemp "$STATUS.XXXXXX")
    jq "$@" <<<"$previous" >"$tmp"
    mv "$tmp" "$STATUS"
    # A bar that isn't running, as on a run from a TTY, is no reason to fail the hook and with it the backup.
    pkill -x -RTMIN+5 waybar || true
}

# The run's own hooks are told nothing about what it did, so the numbers have to be asked for once more.
# Retrying would hold the finished run open for half an hour over two numbers.
# borgmatic prints one result per action, in the order they are named.
statistics() {
    borgmatic --config "$1" --retries 0 info --archive latest --json repo-list --json |
        jq -ce '{added_bytes: .[0].archives[0].stats.deduplicated_size, archives: (.[1].archives | length)}
            | select(.added_bytes | type == "number")'
}

# borgmatic tells its hooks nothing about why a run ended, so the unit is asked instead.
# A stop from outside, by a shutdown, a logout or systemctl stop, puts the unit into deactivating before it sends the TERM; a run that fails by itself leaves it activating.
stopped_from_outside() {
    [ "$(systemctl --user show backup.service --property=ActiveState --value 2>/dev/null)" = deactivating ]
}

case ${1:-} in
start)
    update '.state = "running"'
    ;;
succeed)
    # The success goes in first, so nothing that goes wrong while measuring it can leave a finished backup reading "running".
    update --argjson now "$(date +%s)" '.state = "succeeded" | .last_success = $now | .last_run = $now | .added_bytes = null | .archives = null'
    if stats=$(statistics "$2"); then
        update --argjson stats "$stats" '. + $stats'
    else
        echo "Couldn't read the new archive's statistics; recorded the run without them." >&2
    fi
    ;;
fail)
    state=failed
    if stopped_from_outside; then
        state=interrupted
    fi
    update --arg state "$state" --argjson now "$(date +%s)" '.state = $state | .last_run = $now'
    ;;
*)
    echo "usage: ${0##*/} start | succeed CONFIG | fail" >&2
    exit 2
    ;;
esac
