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

# The module draws entirely with images, so its text is nothing but the spaces they are painted
# over. A label's hit region follows its text and not its CSS padding, so holding the width open
# with padding instead would leave the mark and the rings unhoverable and the tooltip unreachable.
# Non-breaking, because Pango is free to drop ordinary spaces at an edge.
# One per 9.6px at font-size 16px: margin, mark (18px), gap, ring, gap, ring, margin.
SPACER=$'\u00a0\u00a0\u00a0\u00a0\u00a0\u00a0\u00a0\u00a0\u00a0'

# The rings are drawn as SVG rather than picked from the eight nf-md-circle_slice glyphs, so a
# percentage renders at its exact angle. The stylesheet that paints them over the spacer is
# generated here too, and the theme @imports it.
RINGS_CSS="$CACHE_DIR/rings.css"
MARK="$HOME/.config/waybar/claude.svg"
# An image cannot inherit the module's CSS colour, so the palette lookup CSS would have done moves here.
PALETTE="$HOME/.config/waybar/colors.css"
# Progress runs along the rim rather than filling a wedge: a wedge tapers to nothing at the centre,
# so the low percentages that most of a quota's life is spent at read as less than they are.
ARC_WIDTH=5
TRACK_OPACITY=0.45

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
  write_style -1 -1 ok
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
svg_ring() { # $1 = 0..100, or negative for absent; $2 = stroke colour
  awk -v pct="$1" -v col="$2" -v track="$TRACK_OPACITY" -v sw="$ARC_WIDTH" 'BEGIN {
    size = 32; c = size / 2; r = c * 0.95 - sw / 2; pi = 3.141592653589793
    printf "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"%d\" height=\"%d\" viewBox=\"0 0 %d %d\">", size, size, size, size
    if (pct >= 0) {
      printf "<circle cx=\"%g\" cy=\"%g\" r=\"%g\" fill=\"none\" stroke=\"%s\" stroke-opacity=\"%s\" stroke-width=\"%g\"/>", c, c, r, col, track, sw
      # A 100% arc ends where it starts, which draws nothing, so the closed ring is its own case.
      if (pct >= 100)
        printf "<circle cx=\"%g\" cy=\"%g\" r=\"%g\" fill=\"none\" stroke=\"%s\" stroke-width=\"%g\"/>", c, c, r, col, sw
      else if (pct > 0) {
        a = 2 * pi * pct / 100 - pi / 2
        printf "<path d=\"M %g %g A %g %g 0 %d 1 %.2f %.2f\" fill=\"none\" stroke=\"%s\" stroke-width=\"%g\"/>",
          c, c - r, r, r, (pct > 50), c + r * cos(a), c + r * sin(a), col, sw
      }
    }
    printf "</svg>"
  }'
}

# A ring is named after what it draws, so redrawing one is a new url() rather than new bytes behind
# an old one. GTK keeps the decoded image in the style provider and would go on painting the old
# bytes; a name it has never seen has nothing to serve from.
ring_file() { # $1 = 0..100, or negative for absent; $2 = stroke colour; prints the basename
  local name tmp
  if (($1 < 0)); then
    name="ring-none.svg"
  else
    name="ring-$1-${2#\#}.svg"
  fi

  if [ ! -e "$CACHE_DIR/$name" ]; then
    tmp=$(mktemp "$CACHE_DIR/.ring.XXXXXX") || return 1
    if svg_ring "$1" "$2" >"$tmp"; then
      mv -f "$tmp" "$CACHE_DIR/$name" || { rm -f "$tmp"; return 1; }
    else
      rm -f "$tmp"
      return 1
    fi
  fi

  printf '%s' "$name"
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

  # Everything visible is a CSS background image; the text only holds the space open.
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

  write_style "$fh_pct" "$sd_pct" "$class"

  # The tooltip is its own GTK window, so #custom-claude-usage never reaches it and the columns only
  # line up if the markup asks for the monospace font itself.
  jq -cn --arg text "$SPACER" --arg tt "<span font_family=\"JetBrainsMono Nerd Font\">$tooltip</span>" \
    --arg cls "$class" --argjson pct "$maxpct" \
    '{text: $text, class: $cls, tooltip: $tt, percentage: $pct}'
}

# The class only recolours the mascot, so the same three palette entries are resolved here for the
# rings. A wallpaper change rewrites the palette without telling us, so the colour is re-read every
# render and the rings catch up on the next interval.
write_style() { # $1 = five hour percentage, $2 = seven day percentage, $3 = class
  local fill fh sd css tmp
  case $3 in
    crit) fill=$(palette error '#ffb4ab') ;;
    warn) fill=$(palette tertiary '#e5bad8') ;;
    *) fill=$(palette on_surface '#e3e1e9') ;;
  esac

  mkdir -p "$CACHE_DIR" || return
  fh=$(ring_file "$1" "$fill") || return
  sd=$(ring_file "$2" "$fill") || return

  # Waybar's reload_style_on_change watches this file and reloads the style provider alone, where
  # SIGUSR2 would reset the whole bar and every module on it would blink out and shift the layout.
  # url()s resolve against this file, so only the mark, which lives in the stow tree, needs a path.
  css="/* Generated by claude-usage.sh. */
#custom-claude-usage {
    background-image: url(\"$MARK\"), url(\"$fh\"), url(\"$sd\");
    background-repeat: no-repeat, no-repeat, no-repeat;
    background-position: 12px center, 38px center, 62px center;
    background-size: 18px 18px, 16px 16px, 16px 16px;
}"

  [ "$css" = "$(cat "$RINGS_CSS" 2>/dev/null)" ] && return
  tmp=$(mktemp "$CACHE_DIR/.rings.XXXXXX") || return
  if printf '%s\n' "$css" >"$tmp" && mv -f "$tmp" "$RINGS_CSS"; then
    find "$CACHE_DIR" -maxdepth 1 -name 'ring-*.svg' ! -name "$fh" ! -name "$sd" -delete
  else
    rm -f "$tmp"
  fi
}

case "${1:-}" in
feed) feed ;;
*) render ;;
esac
