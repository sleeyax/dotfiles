#!/usr/bin/env bash
# Query ML4W upstream and port individual changes into our vendored tree.
# Upstream lives only as a git remote: refs/remotes/ml4w/* and refs/ml4w-tags/*.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(dirname "$SCRIPT_DIR")"

# shellcheck source=../ml4w-base.env
source "$DOTFILES_DIR/ml4w-base.env"

cd "$DOTFILES_DIR"

usage() {
  cat <<EOF
Usage: $(basename "$0") <command> [args]

  sync                        create the ml4w remote if missing, then fetch
  tags [n]                    list the n most recent upstream tags (default 20)
  show <ver> <path>           print upstream's copy of dotfiles/<path>
  diff <from> <to> [path]     diff dotfiles[/<path>] between two upstream versions
  log <from>..<to> [path]     commits touching dotfiles[/<path>] in the range
  status [path]               diff our home/ against the base version: what we changed
  take <ver> <path>           overwrite home/<path> with upstream's copy
  port <ver> <path>           3-way merge upstream's change into home/<path>

<ver> is an upstream tag (e.g. 2.14.1), "base" for the vendored base
($ML4W_TAG), or any commit-ish.
EOF
}

# Resolve a version argument to something git can read.
_ref() {
  case "$1" in
    base) printf '%s\n' "$ML4W_COMMIT" ;;
    *)
      if git rev-parse --verify --quiet "refs/ml4w-tags/$1" >/dev/null; then
        printf 'refs/ml4w-tags/%s\n' "$1"
      else
        printf '%s\n' "$1"
      fi
      ;;
  esac
}

_require_upstream() {
  if ! git rev-parse --verify --quiet "$ML4W_COMMIT" >/dev/null; then
    echo "Upstream history not fetched. Run: $(basename "$0") sync" >&2
    exit 1
  fi
}

cmd_sync() {
  if ! git remote get-url ml4w >/dev/null 2>&1; then
    git remote add ml4w "$ML4W_REMOTE"
  else
    git remote set-url ml4w "$ML4W_REMOTE"
  fi
  # Upstream tags go into their own namespace so they never show up in `git tag` or get pushed to origin.
  git config remote.ml4w.tagOpt --no-tags
  git config --replace-all remote.ml4w.fetch '+refs/heads/*:refs/remotes/ml4w/*' '\+refs/heads/'
  git config --replace-all remote.ml4w.fetch '+refs/tags/*:refs/ml4w-tags/*' '\+refs/tags/'
  git fetch --filter=blob:none ml4w
}

cmd_tags() {
  git for-each-ref --sort=-creatordate --count="${1:-20}" \
    --format='%(refname:strip=2)  %(creatordate:short)  %(objectname:short)' \
    refs/ml4w-tags
}

cmd_show() {
  [ $# -eq 2 ] || { usage; exit 1; }
  _require_upstream
  git show "$(_ref "$1"):dotfiles/$2"
}

cmd_diff() {
  [ $# -ge 2 ] || { usage; exit 1; }
  _require_upstream
  local sub="dotfiles${3:+/$3}"
  git diff "$(_ref "$1"):$sub" "$(_ref "$2"):$sub"
}

cmd_log() {
  [ $# -ge 1 ] || { usage; exit 1; }
  _require_upstream
  local range="$1" from to
  from="${range%%..*}"
  to="${range##*..}"
  git log --oneline --no-decorate "$(_ref "$from")..$(_ref "$to")" -- "dotfiles${2:+/$2}"
}

cmd_status() {
  _require_upstream
  local pathspec=()
  [ $# -gt 0 ] && pathspec=(-- "$1")
  git diff --stat "$ML4W_COMMIT:dotfiles" "HEAD:home" "${pathspec[@]}"
}

cmd_take() {
  [ $# -eq 2 ] || { usage; exit 1; }
  _require_upstream
  local ref path mode
  ref="$(_ref "$1")"
  path="$2"
  mode=$(git ls-tree "$ref" -- "dotfiles/$path" | awk '{print $1}')
  if [ -z "$mode" ]; then
    echo "Not found upstream: dotfiles/$path" >&2
    exit 1
  fi
  mkdir -p "$(dirname "home/$path")"
  git show "$ref:dotfiles/$path" > "home/$path"
  if [ "$mode" = 100755 ]; then chmod +x "home/$path"; else chmod -x "home/$path"; fi
  echo "Took dotfiles/$path from $1 -> home/$path"
}

cmd_port() {
  [ $# -eq 2 ] || { usage; exit 1; }
  _require_upstream
  local ver path base theirs
  ver="$1"
  path="$2"
  [ -f "home/$path" ] || { echo "No such file: home/$path" >&2; exit 1; }

  # git merge-file mis-handles process substitution, so both sides need real files.
  base=$(mktemp)
  theirs=$(mktemp)
  git show "$ML4W_COMMIT:dotfiles/$path" > "$base"
  git show "$(_ref "$ver"):dotfiles/$path" > "$theirs"

  local rc=0
  git merge-file -L ours -L "ml4w $ML4W_TAG" -L "ml4w $ver" "home/$path" "$base" "$theirs" || rc=$?
  rm -f "$base" "$theirs"

  if [ "$rc" -eq 0 ]; then
    echo "Merged cleanly into home/$path"
  else
    echo "Conflicts left in home/$path — resolve the markers by hand." >&2
    return 1
  fi
}

case "${1:-}" in
  sync)   shift; cmd_sync "$@" ;;
  tags)   shift; cmd_tags "$@" ;;
  show)   shift; cmd_show "$@" ;;
  diff)   shift; cmd_diff "$@" ;;
  log)    shift; cmd_log "$@" ;;
  status) shift; cmd_status "$@" ;;
  take)   shift; cmd_take "$@" ;;
  port)   shift; cmd_port "$@" ;;
  ""|-h|--help|help) usage ;;
  *) echo "Unknown command: $1" >&2; usage >&2; exit 1 ;;
esac
