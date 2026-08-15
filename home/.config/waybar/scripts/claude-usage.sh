#!/usr/bin/env bash
# Waybar readout of the two Claude Code rate limit windows.
#
#   claude-usage.sh        print one line of JSON for waybar (default)
#   claude-usage.sh feed   read statusline JSON on stdin, update the cache, signal waybar on change
#
# There is no network access here: the numbers arrive from ~/.claude/statusline.sh, which is the
# only place Claude Code hands rate_limits to userspace.
set -uo pipefail

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/claude-usage"
CACHE="$CACHE_DIR/usage.json"

CELLS=${CLAUDE_USAGE_CELLS:-10}
TRACK_ALPHA=${CLAUDE_USAGE_TRACK_ALPHA:-35%}
TRACK=${CLAUDE_USAGE_TRACK:-alpha} # alpha | shade

FIVE_HOUR_WINDOW=18000

feed() {
  local new new_body old_body tmp
  new=$(jq -c '{updated_at: (now | floor)} + (.rate_limits // {} | {five_hour, seven_day})') || exit 0
  [ -n "$new" ] || exit 0

  mkdir -p "$CACHE_DIR" || exit 0
  new_body=$(jq -c 'del(.updated_at)' <<<"$new")
  old_body=$(jq -c 'del(.updated_at)' "$CACHE" 2>/dev/null)

  tmp=$(mktemp "$CACHE_DIR/.usage.XXXXXX") || exit 0
  if ! printf '%s\n' "$new" >"$tmp" || ! mv -f "$tmp" "$CACHE"; then
    rm -f "$tmp"
    exit 0
  fi

  # Signalling on every statusline tick would re-exec the module every 300ms for identical numbers.
  [ "$new_body" = "$old_body" ] || pkill -RTMIN+2 waybar
}

hide() {
  jq -cn '{text: "", class: "", tooltip: "", percentage: 0}'
  exit 0
}

rep() { # $1 = glyph, $2 = count
  local i out=''
  for ((i = 0; i < $2; i++)); do out+=$1; done
  printf '%s' "$out"
}

bar() { # $1 = 0..100
  local pct=$1 full empty
  ((pct < 0)) && pct=0
  ((pct > 100)) && pct=100
  full=$(((pct * CELLS + 50) / 100))
  empty=$((CELLS - full))

  printf '%s' "$(rep '█' "$full")"
  ((empty == 0)) && return
  if [ "$TRACK" = shade ]; then
    printf '%s' "$(rep '░' "$empty")"
  else
    printf '<span alpha="%s">%s</span>' "$TRACK_ALPHA" "$(rep '█' "$empty")"
  fi
}

clock_at() { # $1 = epoch seconds
  if [ "$(date -d "@$1" +%F)" = "$(date +%F)" ]; then
    date -d "@$1" +%H:%M
  else
    date -d "@$1" '+%a %H:%M'
  fi
}

fmt_delta() { # $1 = seconds
  local s=$1
  if ((s >= 86400)); then
    printf '%dd %dh' $((s / 86400)) $((s % 86400 / 3600))
  elif ((s >= 3600)); then
    printf '%dh %02dm' $((s / 3600)) $((s % 3600 / 60))
  else
    printf '%dm' $((s / 60))
  fi
}

# The 5-hour window is exactly 5 hours long, so its elapsed fraction is knowable and worth comparing
# against the consumed fraction. The weekly window's true length is not, so it gets no pace figure.
pace() { # $1 = used percentage, $2 = resets_at, $3 = now
  local elapsed diff
  elapsed=$((($3 - ($2 - FIVE_HOUR_WINDOW)) * 100 / FIVE_HOUR_WINDOW))
  ((elapsed < 0 || elapsed > 100)) && return
  diff=$(($1 - elapsed))
  if ((diff > 3)); then
    printf '%d%% ahead of pace' "$diff"
  elif ((diff < -3)); then
    printf '%d%% behind pace' $((-diff))
  else
    printf 'on pace'
  fi
}

# Every field is padded to its widest value ("Tue 14:00", "2d 12h") so the two rows read as columns.
# The tooltip wraps somewhere around 60 characters, which is what keeps the pace figure out of here.
row() { # $1 = label, $2 = used percentage, $3 = resets_at (0 = unknown), $4 = now
  local line
  line=$(printf '%-7s %3d%% used, %3d%% left' "$1" "$2" $((100 - $2)))
  (($3 > 0)) && line+=$(printf '   resets %-9s  in %s' "$(clock_at "$3")" "$(fmt_delta $(($3 - $4)))")
  printf '%s' "$line"
}

render() {
  local updated fh_pct fh_reset sd_pct sd_reset now
  [ -r "$CACHE" ] || hide
  IFS=$'\t' read -r updated fh_pct fh_reset sd_pct sd_reset <<<"$(
    jq -r '[
      .updated_at // 0,
      (.five_hour.used_percentage // -1 | round),
      (.five_hour.resets_at // 0),
      (.seven_day.used_percentage // -1 | round),
      (.seven_day.resets_at // 0)
    ] | @tsv' "$CACHE" 2>/dev/null
  )" || hide
  [ -n "${sd_reset:-}" ] || hide
  ((fh_pct < 0 && sd_pct < 0)) && hide

  now=$(date +%s)

  # resets_at is absolute, so a window whose reset has passed is empty again no matter how stale the
  # cache is. The next window's reset time is not derivable, hence the 0 rather than an extrapolation.
  ((fh_reset > 0 && now >= fh_reset)) && { fh_pct=0; fh_reset=0; }
  ((sd_reset > 0 && now >= sd_reset)) && { sd_pct=0; sd_reset=0; }

  local text='' tooltip='' footer='' pace_txt='' age age_txt maxpct=0 class=ok
  if ((fh_pct >= 0)); then
    text+=$(bar "$fh_pct")
    tooltip+=$(row '5 hour' "$fh_pct" "$fh_reset" "$now")
    ((fh_reset > 0)) && pace_txt=$(pace "$fh_pct" "$fh_reset" "$now")
    [ -n "$pace_txt" ] && footer="5 hour: $pace_txt · "
    ((fh_pct > maxpct)) && maxpct=$fh_pct
  fi
  if ((sd_pct >= 0)); then
    [ -n "$text" ] && text+='  ' # one space lets a full bar merge into the next track
    [ -n "$tooltip" ] && tooltip+=$'\n'
    text+=$(bar "$sd_pct")
    tooltip+=$(row 'Week' "$sd_pct" "$sd_reset" "$now")
    ((sd_pct > maxpct)) && maxpct=$sd_pct
  fi

  age=$((now - updated))
  if ((age < 60)); then
    age_txt='just now'
  else
    age_txt="$(fmt_delta "$age") ago"
  fi
  tooltip+=$'\n\n'"${footer}updated $age_txt"

  ((maxpct >= 75)) && class=warn
  ((maxpct >= 90)) && class=crit

  # The tooltip is its own GTK window, so #custom-claude-usage never reaches it and the columns only
  # line up if the markup asks for the monospace font itself.
  jq -cn --arg text "$text" --arg tt "<span font_family=\"JetBrainsMono Nerd Font\">$tooltip</span>" \
    --arg cls "$class" --argjson pct "$maxpct" \
    '{text: $text, class: $cls, tooltip: $tt, percentage: $pct}'
}

case "${1:-}" in
feed) feed ;;
*) render ;;
esac
