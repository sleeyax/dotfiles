#!/bin/bash
# Bring this machine up to date: the dotfiles, the skills from promptfiles and the paseo plugins.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(dirname "$SCRIPT_DIR")"

SEARCH_ROOTS=("$HOME/Programming" "$HOME/projects")
SEARCH_DEPTH=5

REBUILD_PLUGINS=0
for arg in "$@"; do
  case "$arg" in
    --rebuild-plugins) REBUILD_PLUGINS=1 ;;
    *) echo "Unknown flag: $arg"; exit 1 ;;
  esac
done

STEPS=(dotfiles promptfiles paseo-plugins)
declare -A REPO RESULT MOVED

repos_with_origin() {
  local slug=$1 root git_dir repo url
  local roots=()
  for root in "${SEARCH_ROOTS[@]}"; do
    [ -d "$root" ] && roots+=("$root")
  done
  [ "${#roots[@]}" -gt 0 ] || return 0

  find "${roots[@]}" -maxdepth "$SEARCH_DEPTH" -type d \( -name node_modules -prune -o -name .git -prune -print \) 2>/dev/null |
    while IFS= read -r git_dir; do
      repo=${git_dir%/.git}
      url=$(git -C "$repo" remote get-url origin 2>/dev/null) || continue
      case "$url" in
        *[:/]"$slug" | *[:/]"$slug".git) echo "$repo" ;;
      esac
    done
}

locate_repo() {
  local step=$1 slug=$2
  local matches=()
  mapfile -t matches < <(repos_with_origin "$slug")

  case "${#matches[@]}" in
    0) RESULT[$step]="skipped (no checkout of $slug)" ;;
    1) REPO[$step]=${matches[0]} ;;
    *) RESULT[$step]="failed (several checkouts of $slug: ${matches[*]})" ;;
  esac
}

halt_on_uncommitted_changes() {
  local step repo status dirty=0
  for step in "${STEPS[@]}"; do
    repo=${REPO[$step]:-}
    [ -n "$repo" ] || continue
    if ! status=$(git -C "$repo" status --porcelain); then
      echo "Error: could not read the status of $repo"
      exit 1
    fi
    if [ -n "$status" ]; then
      echo "Uncommitted changes in $repo:"
      echo "$status"
      dirty=1
    fi
  done

  if [ "$dirty" -eq 1 ]; then
    echo "Nothing was updated."
    exit 1
  fi
}

pull_main() {
  local step=$1 repo=${REPO[$1]} before
  before=$(git -C "$repo" rev-parse HEAD)

  if ! git -C "$repo" switch --quiet main || ! git -C "$repo" pull --ff-only; then
    RESULT[$step]="failed (could not update main)"
    return 1
  fi

  if [ "$before" != "$(git -C "$repo" rev-parse HEAD)" ]; then
    MOVED[$step]=1
  fi
}

update_dotfiles() {
  pull_main dotfiles || return

  if "$SCRIPT_DIR/apply.sh"; then
    RESULT[dotfiles]="ok"
  else
    RESULT[dotfiles]="failed (apply.sh)"
  fi
}

skill_names() {
  sed -n 's|.*/\([^/]*\)/SKILL\.md$|\1|p' | sort -u
}

without() {
  grep -Fxv -f <(printf '%s\n' "$2") <<<"$1" | grep .
}

common_to() {
  grep -Fx -f <(printf '%s\n' "$2") <<<"$1" | grep .
}

# The skills CLI keeps its lockfile here, and it records where each skill came from.
skills_lock_path() {
  if [ -n "${XDG_STATE_HOME:-}" ]; then
    echo "$XDG_STATE_HOME/skills/.skill-lock.json"
  else
    echo "$HOME/.agents/.skill-lock.json"
  fi
}

# Other skills repos share ~/.agents/skills, and some reuse names from promptfiles.
skills_from_other_sources() {
  local lock
  lock=$(skills_lock_path)
  [ -f "$lock" ] || return 0
  jq -r '.skills | to_entries[] | select(.value.source | test("(^|/)promptfiles(\\.git)?$") | not) | .key' "$lock" | sort -u
}

update_skills() {
  pull_main promptfiles || return

  local repo=${REPO[promptfiles]} current history foreign installed name
  current=$(git -C "$repo" ls-tree -r --name-only HEAD -- skills | skill_names)
  if [ -z "$current" ]; then
    RESULT[promptfiles]="failed (no skills found on main)"
    return
  fi

  # Only names promptfiles has ever had can be ours to delete, and the lockfile doesn't remember removed ones.
  history=$(git -C "$repo" log --branches --remotes --format= --name-only -- skills | skill_names)

  if ! foreign=$(skills_from_other_sources); then
    RESULT[promptfiles]="failed (could not read the skills lockfile)"
    return
  fi
  installed=$(find "$HOME/.agents/skills" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null)

  while IFS= read -r name; do
    echo "Warning: leaving $name alone, it is installed from another source"
  done < <(common_to "$current" "$foreign")

  local wanted=() stale=()
  mapfile -t wanted < <(without "$current" "$foreign")
  mapfile -t stale < <(without "$(without "$(common_to "$installed" "$history")" "$current")" "$foreign")

  if [ "${#wanted[@]}" -gt 0 ] && ! npx -y skills add "$repo" -s "${wanted[@]}" -g -y </dev/null; then
    RESULT[promptfiles]="failed (skills add)"
    return
  fi

  if [ "${#stale[@]}" -gt 0 ]; then
    printf 'Removing stale skill: %s\n' "${stale[@]}"
    if ! npx -y skills remove -g -y "${stale[@]}" </dev/null; then
      RESULT[promptfiles]="failed (skills remove)"
      return
    fi
  fi

  RESULT[promptfiles]="ok (${#wanted[@]} synced, ${#stale[@]} removed)"
}

update_plugins() {
  pull_main paseo-plugins || return

  # A reload closes every session on the plugin's provider, so it needs a reason.
  if [ "$REBUILD_PLUGINS" -eq 0 ] && [ -z "${MOVED[paseo-plugins]:-}" ]; then
    RESULT[paseo-plugins]="ok (no changes)"
    return
  fi

  local script="${REPO[paseo-plugins]}/scripts/rebuild-plugins.sh"
  if [ ! -x "$script" ]; then
    RESULT[paseo-plugins]="failed (scripts/rebuild-plugins.sh is missing)"
    return
  fi

  if "$script" </dev/null; then
    RESULT[paseo-plugins]="ok (rebuilt)"
  else
    RESULT[paseo-plugins]="failed (rebuild-plugins.sh)"
  fi
}

REPO[dotfiles]=$DOTFILES_DIR
locate_repo promptfiles sleeyax/promptfiles
locate_repo paseo-plugins sleeyax/paseo-plugins

halt_on_uncommitted_changes

for step in "${STEPS[@]}"; do
  [ -n "${REPO[$step]:-}" ] || continue
  echo "==> $step"
  case "$step" in
    dotfiles) update_dotfiles ;;
    promptfiles) update_skills ;;
    paseo-plugins) update_plugins ;;
  esac
done

echo
echo "Summary"
exit_code=0
for step in "${STEPS[@]}"; do
  printf '  %-14s %s\n' "$step" "${RESULT[$step]}"
  case "${RESULT[$step]}" in failed*) exit_code=1 ;; esac
done
exit "$exit_code"
