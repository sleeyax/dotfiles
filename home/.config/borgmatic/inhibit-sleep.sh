#!/usr/bin/env bash
# Runs a command while blocking sleep; backup.service runs borgmatic through it.
# The command replaces this script rather than running under it: systemd sends a stop's SIGTERM to the whole unit and kills what's left once the main process exits, so a wrapper that died first would take borgmatic's fail hook with it.
set -euo pipefail

# Block mode refuses an unprivileged suspend outright; tail --pid ends the block when the command exits.
systemd-inhibit --what=sleep --mode=block --who=borgmatic "--why=Backing up to the Storage Box" tail --pid=$$ -f /dev/null &
exec "$@"
