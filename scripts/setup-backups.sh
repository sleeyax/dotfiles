#!/bin/bash
# Sets this machine up to back up to its own borg repository on the Hetzner Storage Box.
# The guide is docs/backups.md; the rationale is under Backups in AGENTS.md.
# Every step must skip itself when it is already done, so a rerun after a failure picks up where it stopped.
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

# Host key checking would otherwise ask on first contact, which the password upload's askpass would answer with the password.
SSH_OPTS=(-o StrictHostKeyChecking=accept-new)

step() { printf '\n==> %s\n' "$*"; }
skip() { echo "    Already done, skipping."; }
die() { echo "Error: $*" >&2; exit 1; }

# Hetzner requires upper and lower case, a digit and a special character.
random_password() { printf '%sAa1-' "$(openssl rand -hex 24)"; }

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
[ -f "$HOME/.config/borgmatic/config.yaml" ] || die "no borgmatic config; run ./scripts/apply.sh first"

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

step "Create the sub-account $HOST"
subaccount() {
  hcloud storage-box subaccount list "$box" -o json | jq -c --arg name "$HOST" '.[] | select(.name == $name)'
}
sub=$(subaccount)
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

step "Store a borg passphrase in the keyring"
# A lookup fails the same way for a missing item and an unreachable keyring, and storing over a real passphrase would strand the repository.
stored=$(secret-tool search "${SECRET_ATTRIBUTES[@]}" 2>/dev/null) || die "couldn't reach the GNOME keyring; unlock it and rerun"
if [ -n "$stored" ]; then
  skip
else
  openssl rand -base64 32 | tr -d '\n' |
    secret-tool store --label "borgmatic passphrase for $SSH_ALIAS" "${SECRET_ATTRIBUTES[@]}"
fi

unset stored

step "Create the repository"
if borgmatic repo-info >/dev/null 2>&1; then
  skip
else
  borgmatic repo-create
fi

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
repository_id=$(borgmatic repo-info --json | jq -r '.[0].repository.id')
if [ "$(cat "$SECRETS_SHOWN" 2>/dev/null)" = "$repository_id" ]; then
  skip
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
  mkdir -p "$(dirname "$SECRETS_SHOWN")"
  echo "$repository_id" >"$SECRETS_SHOWN"
fi

cat <<'EOF'

Done. This machine can back up to the Storage Box.
Delete the API token in the Hetzner Console now; nothing on this machine needs it again.
EOF
