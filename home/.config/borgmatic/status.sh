#!/usr/bin/env bash
# Records each backup run in the status file the bar and the staleness check read; borgmatic's hooks in config.yaml call it.
# The file's fields are the contract under Backups in AGENTS.md.
#
#   status.sh start            a run is starting
#   status.sh succeed CONFIG   the run CONFIG drove succeeded
#   status.sh fail             the run failed, after every retry
set -euo pipefail

STATUS="${XDG_STATE_HOME:-$HOME/.local/state}/backup/status.json"

# Applies a jq filter to the previous status and replaces it in one rename, so a reader never sees half a file.
update() {
    mkdir -p "${STATUS%/*}"
    local previous tmp
    previous=$(jq -c . "$STATUS" 2>/dev/null) || previous='{}'
    tmp=$(mktemp "$STATUS.XXXXXX")
    jq "$@" <<<"$previous" >"$tmp"
    mv "$tmp" "$STATUS"
}

# The run's own hooks are told nothing about what it did, so the numbers have to be asked for once more, while the repository is still reachable.
# Retrying would hold the finished run open for half an hour over two numbers.
statistics() {
    borgmatic --config "$1" --retries 0 info --archive latest --json repo-list --json
}

case ${1:-} in
start)
    update '.state = "running"'
    ;;
succeed)
    if ! stats=$(statistics "$2"); then
        echo "Couldn't read the new archive's statistics; recording the run without them." >&2
        stats=null
    fi
    update --argjson now "$(date +%s)" --argjson stats "$stats" '
        .state = "succeeded"
        | .last_success = $now
        | .added_bytes = ($stats | if . then map(select(.archives[0].stats))[0].archives[0].stats.deduplicated_size else null end)
        | .archives = ($stats | if . then map(select(.archives[0].stats | not))[0].archives | length else null end)'
    ;;
fail)
    update '.state = "failed"'
    ;;
*)
    echo "usage: ${0##*/} start | succeed CONFIG | fail" >&2
    exit 2
    ;;
esac
