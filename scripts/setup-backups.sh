#!/bin/bash
# Sets this machine up to back up to its own borg repository on the Hetzner Storage Box.
# With --restore, it instead reconnects a machine that replaces a lost one to the backups that machine left, and leaves backups off.
# The guide is docs/backups.md; the rationale is under Backups in AGENTS.md.
# Every step must skip itself when it is already done, or be harmless to repeat, so a rerun after a failure picks up where it stopped.
set -euo pipefail
umask 077

HOST=$(uname -n)
SSH_ALIAS=storagebox
SSH_KEY="$HOME/.ssh/storagebox"
SSH_CONFIG="$HOME/.ssh/config"
# The same path as the ./borg in the tracked config's repository, relative to the sub-account's home.
REPOSITORY_PATH=./borg
SECRET_ATTRIBUTES=(service borgmatic repository storagebox)
# Holds the ID of the repository whose passphrase and key were last shown, so a recreated repository shows its own.
SECRETS_SHOWN="${XDG_STATE_HOME:-$HOME/.local/state}/backup/setup-secrets-shown"
# borg's exit codes for the two ways a repository can fail to open; borgmatic asks borg for these specific ones.
REPOSITORY_MISSING=13
PASSPHRASE_WRONG=52

# Host key checking would otherwise ask on first contact, which the password upload's askpass would answer with the password.
SSH_OPTS=(-o StrictHostKeyChecking=accept-new)

step() { printf '\n==> %s\n' "$*"; }
skip() { echo "    Already done, skipping."; }
die() { echo "Error: $*" >&2; exit 1; }

# Hetzner requires upper and lower case, a digit and a special character.
random_password() { printf '%sAa1-' "$(openssl rand -hex 24)"; }

random_passphrase() { openssl rand -base64 32 | tr -d '\n'; }

ssh_option() { ssh -G "$SSH_ALIAS" | awk -v key="$1" '$1 == key && !found { print $2; found = 1 }'; }

# Without a HostName, ssh -G reports the alias itself as the host.
alias_configured() { [ "$(ssh_option hostname)" != "$SSH_ALIAS" ]; }

# ssh takes the first value it finds for each option, so an earlier Host block can override ours.
check_alias() {
  local actual
  actual=$(ssh_option "$1")
  [ "$actual" = "$2" ] ||
    die "$SSH_CONFIG gives $SSH_ALIAS the $1 $actual, not $2; fix the Host block that sets it and rerun"
}

# A new sub-account's hostname takes a few minutes to appear in DNS.
wait_for_dns() {
  local deadline=$((SECONDS + 600))
  until getent hosts "$1" >/dev/null; do
    [ "$SECONDS" -lt "$deadline" ] || die "$1 still doesn't resolve after 10 minutes; rerun the script later"
    echo "    Waiting for $1 to appear in DNS..."
    sleep 15
  done
}

# Authentication failing is ssh's 255; anything else means the key got in and the forced command ran.
key_installed() {
  local status=0
  ssh -n -o BatchMode=yes "${SSH_OPTS[@]}" "$SSH_ALIAS" true >/dev/null 2>&1 || status=$?
  [ "$status" -ne 255 ]
}

# Sets repository_status to borg's exit code, 0 when the passphrase opened the repository, and probe_output to what borgmatic printed.
# borg looks for the repository before it tries the passphrase, so even a random one tells a missing repository from an existing one.
# borgmatic exits 1 whatever went wrong, so borg's own code is read out of its log.
probe_repository() {
  if probe_output=$(SETUP_PASSPHRASE="$1" BACKUP_PASSCOMMAND='printenv SETUP_PASSPHRASE' borgmatic repo-list 2>&1); then
    repository_status=0
  else
    repository_status=$(grep -oP 'returned non-zero exit status \K[0-9]+' <<<"$probe_output" | tail -n 1 || true)
  fi
}

probe_stored_passphrase() {
  local passphrase
  passphrase=$(secret-tool lookup "${SECRET_ATTRIBUTES[@]}") || die "couldn't read the passphrase from the GNOME keyring; unlock it and rerun"
  probe_repository "$passphrase"
}

repository_error() {
  printf '%s\n' "$probe_output" >&2
  die "couldn't open $HOST's repository; borgmatic's output is above"
}

case "$#:${1-}" in
  0:) RESTORE=0 ;;
  1:--restore) RESTORE=1 ;;
  *) die "usage: $0 [--restore]" ;;
esac

if ! command -v hcloud &>/dev/null; then
  cat >&2 <<'EOF'
Error: hcloud, Hetzner's command-line tool, is not installed.
It is only needed while setting a machine up, so it isn't in the package lists:
  sudo pacman -S hcloud
EOF
  exit 1
fi

if [ -z "${HCLOUD_TOKEN:-}" ]; then
  cat >&2 <<'EOF'
Error: HCLOUD_TOKEN is not set.
Create an API token in the Hetzner Console (see One-time setup in docs/backups.md), then:
  read -rs HCLOUD_TOKEN && export HCLOUD_TOKEN
EOF
  exit 1
fi

for cmd in borgmatic secret-tool ssh ssh-keygen sftp jq openssl; do
  command -v "$cmd" &>/dev/null || die "$cmd not found; run ./scripts/apply.sh first"
done
for file in borgmatic/config.yaml systemd/user/backup.timer; do
  [ -f "$HOME/.config/$file" ] || die "no ~/.config/$file; run ./scripts/apply.sh first"
done

hcloud() { command hcloud --no-experimental-warnings "$@"; }

# Every call here is a probe or a one-off, which shouldn't sit out half an hour of retries.
borgmatic() { command borgmatic --retries 0 "$@"; }

# The test overrides would point every borgmatic call below at a throwaway repository.
unset BACKUP_REPOSITORY BACKUP_PASSCOMMAND

step "Find the Storage Box"
boxes=$(hcloud storage-box list -o json)
case $(jq length <<<"$boxes") in
  0) die "the token's project has no Storage Box" ;;
  1) ;;
  *) die "the token's project has more than one Storage Box, and this script only knows how to pick the only one" ;;
esac
box=$(jq -r '.[0].id' <<<"$boxes")
echo "    Using $(jq -r '.[0].name' <<<"$boxes") ($(jq -r '.[0].server' <<<"$boxes"))."

subaccount() {
  hcloud storage-box subaccount list "$box" -o json | jq -c --arg name "$HOST" '.[] | select(.name == $name)'
}
sub=$(subaccount)
if [ "$RESTORE" = 1 ]; then
  step "Find the sub-account $HOST"
  [ -n "$sub" ] ||
    die "the Storage Box has no sub-account named $HOST, so no backups to restore under this hostname; give this machine the lost one's hostname with 'sudo hostnamectl hostname <name>' and rerun"
else
  step "Create the sub-account $HOST"
  if [ -n "$sub" ]; then
    skip
  else
    # The API documents no defaults for the access settings, so every one is spelled out.
    # The password is never used: the key upload below sets its own.
    hcloud storage-box subaccount create "$box" \
      --name "$HOST" \
      --home-directory "backups/$HOST" \
      --password "$(random_password)" \
      --enable-ssh=true \
      --reachable-externally=true \
      --enable-samba=false \
      --enable-webdav=false \
      --readonly=false >/dev/null
    sub=$(subaccount)
    [ -n "$sub" ] || die "the sub-account was created but doesn't show up in the list"
  fi
fi
sub_id=$(jq -r .id <<<"$sub")
sub_user=$(jq -r .username <<<"$sub")
sub_server=$(jq -r .server <<<"$sub")
echo "    $sub_user, home backups/$HOST."

step "Generate the SSH key $SSH_KEY"
if [ -f "$SSH_KEY" ]; then
  skip
else
  mkdir -p "$(dirname "$SSH_KEY")"
  # Backups run unattended, so the key can't have a passphrase.
  ssh-keygen -q -t ed25519 -N '' -C "borgmatic@$HOST" -f "$SSH_KEY"
fi

step "Add the $SSH_ALIAS host to $SSH_CONFIG"
if alias_configured; then
  skip
else
  if [ -s "$SSH_CONFIG" ]; then echo >>"$SSH_CONFIG"; fi
  # ServerAlive* fails a dead connection after about 3 minutes, rather than leaving a backup hanging all night.
  cat >>"$SSH_CONFIG" <<EOF
# This machine's Storage Box sub-account, which borgmatic's config reaches by this name.
Host $SSH_ALIAS
    HostName $sub_server
    User $sub_user
    Port 23
    IdentityFile $SSH_KEY
    IdentitiesOnly yes
    ServerAliveInterval 30
    ServerAliveCountMax 6
EOF
fi
check_alias hostname "$sub_server"
check_alias user "$sub_user"
check_alias port 23

step "Install the restricted key on the Storage Box"
wait_for_dns "$sub_server"
if key_installed; then
  skip
else
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT

  printf 'command="borg-1.4 serve --restrict-to-repository %s",restrict %s\n' \
    "$REPOSITORY_PATH" "$(cat "$SSH_KEY.pub")" >"$tmp/authorized_keys"

  # The password reaches ssh through the environment, so it is never written to disk.
  cat >"$tmp/askpass" <<'EOF'
#!/bin/sh
printf '%s\n' "$SETUP_PASSWORD"
EOF
  chmod 700 "$tmp/askpass"

  password=$(random_password)
  hcloud storage-box subaccount reset-password "$box" "$sub_id" --password "$password" >/dev/null

  # Batch mode would force BatchMode=yes onto ssh, which rules out a password.
  # Without it, sftp's exit status says nothing about the commands, so whether the key gets in afterwards is the test.
  SETUP_PASSWORD="$password" SSH_ASKPASS="$tmp/askpass" SSH_ASKPASS_REQUIRE=force \
    sftp -o PubkeyAuthentication=no -o PreferredAuthentications=password,keyboard-interactive \
    -o NumberOfPasswordPrompts=1 "${SSH_OPTS[@]}" "$SSH_ALIAS" >/dev/null <<EOF || true
-mkdir .ssh
-chmod 700 .ssh
put $tmp/authorized_keys .ssh/authorized_keys
-chmod 600 .ssh/authorized_keys
EOF

  # Whether or not the upload worked, the one-time password must not outlive it.
  hcloud storage-box subaccount reset-password "$box" "$sub_id" --password "$(random_password)" >/dev/null
  unset password

  key_installed || die "the Storage Box doesn't accept the key; the upload above failed"
fi

# A lookup fails the same way for a missing item and an unreachable keyring, and storing over a real passphrase would strand the repository.
stored=$(secret-tool search "${SECRET_ATTRIBUTES[@]}" 2>/dev/null) || die "couldn't reach the GNOME keyring; unlock it and rerun"

store_passphrase() {
  printf '%s' "$1" | secret-tool store --label "borgmatic passphrase for $SSH_ALIAS" "${SECRET_ATTRIBUTES[@]}"
}

if [ "$RESTORE" = 1 ]; then
  step "Store the passphrase from KeePassXC in the keyring"
  if [ -n "$stored" ]; then probe_stored_passphrase; else probe_repository "$(random_passphrase)"; fi
  case $repository_status in
    0) skip ;;
    "$REPOSITORY_MISSING")
      die "the Storage Box holds no repository for $HOST, so there is nothing to restore; restore mode never creates one" ;;
    "$PASSPHRASE_WRONG")
      [ -z "$stored" ] || echo "    The keyring's passphrase doesn't open the repository, so it will be replaced."
      while :; do
        read -rsp "    Passphrase for $HOST's repository, from KeePassXC: " passphrase || die "no passphrase given"
        echo
        [ -n "$passphrase" ] || continue
        probe_repository "$passphrase"
        [ "$repository_status" = "$PASSPHRASE_WRONG" ] || break
        echo "    That passphrase doesn't open the repository; try again."
      done
      [ "$repository_status" = 0 ] || repository_error
      store_passphrase "$passphrase"
      unset passphrase
      ;;
    *) repository_error ;;
  esac
else
  step "Store a borg passphrase in the keyring"
  if [ -n "$stored" ]; then
    skip
  else
    passphrase=$(random_passphrase)
    probe_repository "$passphrase"
    case $repository_status in
      "$REPOSITORY_MISSING") ;;
      "$PASSPHRASE_WRONG")
        die "the Storage Box already holds a repository for $HOST, so this machine replaces one; rerun with --restore to reconnect it with the passphrase from KeePassXC" ;;
      *) repository_error ;;
    esac
    store_passphrase "$passphrase"
    unset passphrase
  fi

  step "Create the repository"
  probe_stored_passphrase
  case $repository_status in
    0) skip ;;
    "$REPOSITORY_MISSING") borgmatic repo-create ;;
    "$PASSPHRASE_WRONG")
      die "the keyring's passphrase doesn't open $HOST's repository; if this machine replaces one, rerun with --restore" ;;
    *) repository_error ;;
  esac
fi

unset stored

step "Check the key reaches borg 1.4 and nothing else"
versions=$(borgmatic borg version) || die "couldn't ask the Storage Box which borg it runs"
[[ $versions == *" / "* ]] || die "borg reported no server version: $versions"
server_version=${versions##* / }
case "$server_version" in
  1.4.*) echo "    The Storage Box runs borg $server_version for this key." ;;
  *) die "the Storage Box runs borg $server_version for this key, not 1.4" ;;
esac
if timeout 60 sftp -b /dev/null "${SSH_OPTS[@]}" "$SSH_ALIAS" >/dev/null 2>&1; then
  die "the key can open an SFTP session, so its authorized_keys entry isn't restricted"
fi
echo "    The key can't open an SFTP session."

step "Save the passphrase and the key export"
repository_id=$(borgmatic repo-list --json | jq -r '.[0].repository.id')
if [ "$(cat "$SECRETS_SHOWN" 2>/dev/null)" = "$repository_id" ]; then
  skip
else
  if [ "$RESTORE" = 1 ]; then
    echo "    The passphrase is the one from KeePassXC and the key the one on paper, so there is nothing new to save."
  else
    cat <<EOF

Without both of these, nobody can read the backups once this machine is gone, including you.

Passphrase, for KeePassXC:

    $(secret-tool lookup "${SECRET_ATTRIBUTES[@]}")

Key export, for paper:

EOF
    borgmatic key export --paper
    echo
    read -rp "Press Enter once the passphrase is in KeePassXC and the key is printed. "
  fi
  mkdir -p "$(dirname "$SECRETS_SHOWN")"
  echo "$repository_id" >"$SECRETS_SHOWN"
fi

box_json() { hcloud storage-box describe "$box" -o json; }

step "Snapshot the whole box every Sunday at 00:00 UTC, keeping 10"
# hcloud prints Sunday as 0 where the API stores 7, so either counts.
snapshot_plan_set() {
  box_json | jq -e '.snapshot_plan // {} |
    .max_snapshots == 10 and .hour == 0 and .minute == 0 and .day_of_month == null and
    (.day_of_week | . != null and . % 7 == 0)' >/dev/null
}
if snapshot_plan_set; then
  skip
else
  hcloud storage-box enable-snapshot-plan "$box" \
    --day-of-week Sunday --hour 0 --minute 0 --max-snapshots 10 >/dev/null
  snapshot_plan_set || die "the snapshot plan was set, but hcloud describes a different one"
fi

step "Turn off Samba and WebDAV on the main account"
main_shares_off() { box_json | jq -e '.access_settings | (.samba_enabled or .webdav_enabled) | not' >/dev/null; }
if main_shares_off; then
  skip
else
  hcloud storage-box update-access-settings "$box" --enable-samba=false --enable-webdav=false >/dev/null
  main_shares_off || die "the access settings were updated, but the main account still has Samba or WebDAV on"
fi

step "Reset the main account's password to one nobody knows"
# Whether anyone still knows the password can't be observed, and replacing an unknown password with another changes nothing, so this never skips.
hcloud storage-box reset-password "$box" --password "$(random_password)" >/dev/null

if [ "$RESTORE" = 1 ]; then
  # Until the files are back, a backup would archive a near-empty home and prune a real archive to make room for it.
  step "Keep the evening backups off"
  if systemctl --user is-enabled --quiet backup.timer; then
    systemctl --user disable --now backup.timer
  else
    skip
  fi

  cat <<EOF

Done. This machine can read $HOST's backups, and won't back up until you turn the evening backups back on.
Delete the API token in the Hetzner Console now; nothing on this machine needs it again.
Then restore your files: see Restoring a whole machine in docs/backups.md.
EOF
  exit 0
fi

# Last, so a machine whose setup stopped partway never fails a backup every evening.
step "Back up every evening"
if systemctl --user is-enabled --quiet backup.timer; then
  skip
else
  systemctl --user daemon-reload
  systemctl --user enable --now backup.timer
fi

cat <<'EOF'

Done. This machine backs up to the Storage Box every evening at 19:00.
Delete the API token in the Hetzner Console now; nothing on this machine needs it again.
EOF
