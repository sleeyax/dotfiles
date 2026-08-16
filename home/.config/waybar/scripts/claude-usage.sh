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

# The Claude starburst as a Unicode character (U+2733) is absent from JetBrainsMono Nerd Font and
# falls back to Noto Color Emoji, which is a fixed colour and a different advance width.
# nf-fa-asterisk is the same shape, in the font already in use, and takes the module's CSS colour.
MASCOT=$'\uF069' # nf-fa-asterisk
# The label's hit region follows its text, not its CSS padding, so every margin here is spaces
# rather than padding: with padding, the discs are unhoverable and the tooltip only appears
# over the mascot itself. Non-breaking, because Pango is free to drop ordinary ones at an edge.
LEAD=$'\u00a0'
SPACER=$'\u00a0\u00a0\u00a0\u00a0\u00a0\u00a0'

# The discs are drawn as SVG rather than picked from the eight nf-md-circle_slice glyphs, so a
# percentage renders at its exact angle. style.css points at these paths and paints them over the
# spacer that follows the mascot.
FIVE_HOUR_SVG="$CACHE_DIR/five_hour.svg"
SEVEN_DAY_SVG="$CACHE_DIR/seven_day.svg"
# An image cannot inherit the module's CSS colour, so the palette lookup CSS would have done moves here.
PALETTE="$HOME/.config/waybar/colors.css"
# The ring is the outline of the disc, not a dimmed track: at 16px a faint one disappears against the pill.
TRACK_OPACITY=1
TRACK_WIDTH=3

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

palette() { # $1 = matugen colour name, $2 = fallback
  local hex
  hex=$(sed -n "s/.*@define-color[[:space:]]\+$1[[:space:]]\+\(#[0-9a-fA-F]\+\).*/\1/p" "$PALETTE" 2>/dev/null | head -1)
  printf '%s' "${hex:-$2}"
}

# A window that is absent renders as nothing at all rather than as an empty ring, which would claim
# the quota is untouched.
svg_disc() { # $1 = 0..100, or negative for absent; $2 = fill colour
  awk -v pct="$1" -v fill="$2" -v track="$TRACK_OPACITY" -v sw="$TRACK_WIDTH" 'BEGIN {
    size = 32; c = size / 2; r = c * 0.86 - sw / 2; pi = 3.141592653589793
    printf "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"%d\" height=\"%d\" viewBox=\"0 0 %d %d\">", size, size, size, size
    if (pct >= 0) {
      printf "<circle cx=\"%g\" cy=\"%g\" r=\"%g\" fill=\"none\" stroke=\"%s\" stroke-opacity=\"%s\" stroke-width=\"%g\"/>", c, c, r, fill, track, sw
      # A 100% arc ends where it starts, which draws nothing, so the full disc is its own case.
      if (pct >= 100)
        printf "<circle cx=\"%g\" cy=\"%g\" r=\"%g\" fill=\"%s\"/>", c, c, r, fill
      else if (pct > 0) {
        a = 2 * pi * pct / 100 - pi / 2
        printf "<path d=\"M %g %g L %g %g A %g %g 0 %d 1 %.2f %.2f Z\" fill=\"%s\"/>",
          c, c, c, c - r, r, r, (pct > 50), c + r * cos(a), c + r * sin(a), fill
      }
    }
    printf "</svg>"
  }'
}

write_disc() { # $1 = path, $2 = svg; true when the file changed
  [ "$2" = "$(cat "$1" 2>/dev/null)" ] && return 1
  local tmp
  tmp=$(mktemp "$CACHE_DIR/.disc.XXXXXX") || return 1
  printf '%s\n' "$2" >"$tmp" && mv -f "$tmp" "$1" && return 0
  rm -f "$tmp"
  return 1
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

  # The text is only the mascot and its spacer; the discs are CSS backgrounds painted over the latter.
  local tooltip='' footer='' pace_txt='' age age_txt maxpct=0 class=ok
  if ((fh_pct >= 0)); then
    tooltip+=$(row '5 hour' "$fh_pct" "$fh_reset" "$now")
    ((fh_reset > 0)) && pace_txt=$(pace "$fh_pct" "$fh_reset" "$now")
    [ -n "$pace_txt" ] && footer="5 hour: $pace_txt · "
    ((fh_pct > maxpct)) && maxpct=$fh_pct
  fi
  if ((sd_pct >= 0)); then
    [ -n "$tooltip" ] && tooltip+=$'\n'
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
  jq -cn --arg text "$LEAD$MASCOT$SPACER" --arg tt "<span font_family=\"JetBrainsMono Nerd Font\">$tooltip</span>" \
    --arg cls "$class" --argjson pct "$maxpct" \
    '{text: $text, class: $cls, tooltip: $tt, percentage: $pct}'

  # Emitted first: repainting the discs restarts every module, which would otherwise discard this line.
  draw_discs "$fh_pct" "$sd_pct" "$class"
}

# The class only recolours the mascot, so the same three palette entries are resolved here for the
# discs. A wallpaper change rewrites the palette without telling us, so the colour is re-read every
# render and the discs catch up on the next interval.
draw_discs() { # $1 = five hour percentage, $2 = seven day percentage, $3 = class
  local fill changed=1
  case $3 in
    crit) fill=$(palette error '#ffb4ab') ;;
    warn) fill=$(palette tertiary '#e5bad8') ;;
    *) fill=$(palette on_surface '#e3e1e9') ;;
  esac

  mkdir -p "$CACHE_DIR" || return
  write_disc "$FIVE_HOUR_SVG" "$(svg_disc "$1" "$fill")" && changed=0
  write_disc "$SEVEN_DAY_SVG" "$(svg_disc "$2" "$fill")" && changed=0

  # GTK holds the decoded image in the style provider, so only a stylesheet reload picks up a
  # rewritten disc. That reload covers the whole bar, hence only on an actual change.
  ((changed)) || pkill -USR2 waybar
}

case "${1:-}" in
feed) feed ;;
*) render ;;
esac
