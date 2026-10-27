#!/usr/bin/env bash
# Lists what the newest backup changed: every file added, removed or modified since the archive before it, with the size of each change.
# The waybar icon runs it on a right click; the guide's "Running a backup by hand" explains the output.
set -euo pipefail

# A failure is reported at once rather than retried for half an hour.
names=$(borgmatic --retries 0 repo-list --last 2 --json | jq -r '.[0].archives[].name')
mapfile -t archives <<<"$names"
if ((${#archives[@]} < 2)); then
    echo "Nothing to compare yet: the repository holds fewer than two archives."
    exit
fi

echo "Changes from ${archives[0]} to ${archives[1]}"
echo "Both archives' file lists are read from the Storage Box, so this can take a minute or so."
echo
# Without --content-only, every file whose timestamps changed is listed too, even with its contents unchanged.
borgmatic --retries 0 diff --archive "${archives[0]}" --second-archive "${archives[1]}" --content-only
