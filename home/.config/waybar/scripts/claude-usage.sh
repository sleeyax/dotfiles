#!/usr/bin/env bash
# Waybar readout of the Claude Code rate limit windows.
#
#   claude-usage.sh        print one line of JSON for waybar (default)
#   claude-usage.sh fetch  ask Anthropic for the windows, cache them, signal waybar on change
#
# Asking is the only way to have the numbers at all. The statusline is the one place Claude Code
# hands `rate_limits` to userspace, and it only renders in the terminal client, so a session driven
# through the SDK (like T3 Code) produces none. `render` starts a `fetch` when the last one has aged.
set -uo pipefail

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/claude-usage"
CACHE="$CACHE_DIR/usage.json"

# The one surface that reports the windows as percentages, and where the statusline's own numbers
# come from. It is undocumented, so a shape change has to degrade rather than break: a failed fetch
# leaves the last cache on the bar with its age in the tooltip.
USAGE_URL="https://api.anthropic.com/api/oauth/usage"
# Whichever client is running keeps this token fresh, T3 Code included, so nothing here refreshes it.
CREDENTIALS="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.credentials.json"
# Waybar re-execs this script every 30s, which is far oftener than the windows move and far oftener
# than an undocumented endpoint deserves to be asked.
REFRESH_INTERVAL=300
ATTEMPTED="$CACHE_DIR/last-fetch"

# The module draws entirely with images, so its text is nothing but the spaces they are painted
# over. A label's hit region follows its text and not its CSS padding, so holding the width open
# with padding instead would leave the mark and the rings unhoverable and the tooltip unreachable.
# Geometry of those images, in px at font-size 16px; the spacer count follows from the ring count.
# The mark needs no term in the width, since it sits inside the first ring's lead-in.
SPACER_ADVANCE=96 # tenths of a px, so the spacer count divides in integers
MARK_X=12
MARK_SIZE=18
RING_X=38
RING_SIZE=16
RING_PITCH=24
TRAIL=8 # right margin past the last ring

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

# Neither window's length is in the response, only its reset time. Both are named by their length
# instead — the weekly one twice, as `seven_day` and as `weekly_all` — so a window's start is its
# reset minus its length and the fraction of it that has elapsed is knowable.
FIVE_HOUR_WINDOW=18000
SEVEN_DAY_WINDOW=604800

feed() { # rate_limits JSON on stdin
  local new new_body old_body tmp
  new=$(jq -c '{updated_at: (now | floor)} + (.rate_limits // {} | {five_hour, seven_day})') || return 1
  [ -n "$new" ] || return 1

  mkdir -p "$CACHE_DIR" || return 1
  new_body=$(jq -c 'del(.updated_at)' <<<"$new")
  old_body=$(jq -c 'del(.updated_at)' "$CACHE" 2>/dev/null)

  tmp=$(mktemp "$CACHE_DIR/.usage.XXXXXX") || return 1
  if ! printf '%s\n' "$new" >"$tmp" || ! mv -f "$tmp" "$CACHE"; then
    rm -f "$tmp"
    return 1
  fi

  # A percentage moves a few times an hour at most, so most fetches come back identical and a signal
  # per fetch would re-exec the module for nothing.
  [ "$new_body" = "$old_body" ] || pkill -RTMIN+2 waybar
}

epoch() { # $1 = ISO 8601 timestamp, or empty
  [ -n "$1" ] || return 0
  date -d "$1" +%s 2>/dev/null
}

# The response names the same two windows twice: an older five_hour/seven_day pair, and a limits[]
# array keyed by kind. Reading both means either one going away costs nothing.
# A plan may have no five hour window at all, so any field can be empty, and the fields are split on
# a non-whitespace separator because read collapses a run of whitespace ones, tabs included.
fetch() {
  local token body five_pct five_at seven_pct seven_at payload
  token=$(jq -r '.claudeAiOauth.accessToken // empty' "$CREDENTIALS" 2>/dev/null)
  if [ -z "$token" ]; then
    echo "claude-usage: no OAuth token in $CREDENTIALS" >&2
    return 1
  fi

  body=$(curl -fsS --max-time 10 \
    -H "Authorization: Bearer $token" \
    -H 'anthropic-beta: oauth-2025-04-20' \
    -H 'Content-Type: application/json' \
    "$USAGE_URL") || {
    echo "claude-usage: GET $USAGE_URL failed" >&2
    return 1
  }

  IFS=$'\x1f' read -r five_pct five_at seven_pct seven_at <<<"$(
    jq -r '
      def window($obj; $kind):
        ([.limits[]? | select(.kind == $kind and (.percent | type) == "number")] | first) as $limit
        | if $limit then [$limit.percent, $limit.resets_at]
          elif (($obj | type) == "object" and ($obj.utilization | type) == "number")
            then [$obj.utilization, $obj.resets_at]
          else [null, null]
          end;
      window(.five_hour; "session") + window(.seven_day; "weekly_all") | map(. // "" | tostring) | join("\u001f")
    ' <<<"$body" 2>/dev/null
  )"

  if [ -z "$five_pct" ] && [ -z "$seven_pct" ]; then
    echo "claude-usage: no usable windows in the response from $USAGE_URL" >&2
    return 1
  fi

  payload=$(jq -cn \
    --arg fp "$five_pct" --arg fr "$(epoch "$five_at")" \
    --arg sp "$seven_pct" --arg sr "$(epoch "$seven_at")" '
    def window($pct; $reset):
      if $pct == "" then null
      else {used_percentage: ($pct | tonumber)}
        + (if $reset == "" then {} else {resets_at: ($reset | tonumber)} end)
      end;
    {rate_limits: ({five_hour: window($fp; $fr), seven_day: window($sp; $sr)}
      | with_entries(select(.value != null)))}
  ') || return 1

  feed <<<"$payload"
}

# The marker records attempts rather than successes, so a broken endpoint is asked no oftener than a
# working one.
maybe_refresh() { # $1 = now
  local attempted
  attempted=$(stat -c %Y "$ATTEMPTED" 2>/dev/null)
  [[ $attempted =~ ^[0-9]+$ ]] || attempted=0
  (($1 - attempted < REFRESH_INTERVAL)) && return

  mkdir -p "$CACHE_DIR" || return
  touch "$ATTEMPTED" || return
  # Waybar reads this script's stdout until it closes, so the fetch cannot be left holding it open.
  fetch >/dev/null 2>&1 &
}

hide() {
  write_style ok
  jq -cn '{text: "", class: "", tooltip: "", percentage: 0}'
  exit 0
}

palette() { # $1 = matugen colour name, $2 = fallback
  local hex
  hex=$(sed -n "s/.*@define-color[[:space:]]\+$1[[:space:]]\+\(#[0-9a-fA-F]\+\).*/\1/p" "$PALETTE" 2>/dev/null | head -1)
  printf '%s' "${hex:-$2}"
}

svg_ring() { # $1 = 0..100; $2 = stroke colour
  awk -v pct="$1" -v col="$2" -v track="$TRACK_OPACITY" -v sw="$ARC_WIDTH" 'BEGIN {
    size = 32; c = size / 2; r = c * 0.95 - sw / 2; pi = 3.141592653589793
    printf "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"%d\" height=\"%d\" viewBox=\"0 0 %d %d\">", size, size, size, size
    printf "<circle cx=\"%g\" cy=\"%g\" r=\"%g\" fill=\"none\" stroke=\"%s\" stroke-opacity=\"%s\" stroke-width=\"%g\"/>", c, c, r, col, track, sw
    # A 100% arc ends where it starts, which draws nothing, so the closed ring is its own case.
    if (pct >= 100)
      printf "<circle cx=\"%g\" cy=\"%g\" r=\"%g\" fill=\"none\" stroke=\"%s\" stroke-width=\"%g\"/>", c, c, r, col, sw
    else if (pct > 0) {
      a = 2 * pi * pct / 100 - pi / 2
      printf "<path d=\"M %g %g A %g %g 0 %d 1 %.2f %.2f\" fill=\"none\" stroke=\"%s\" stroke-width=\"%g\"/>",
        c, c - r, r, r, (pct > 50), c + r * cos(a), c + r * sin(a), col, sw
    }
    printf "</svg>"
  }'
}

# A ring is named after what it draws, so redrawing one is a new url() rather than new bytes behind
# an old one. GTK keeps the decoded image in the style provider and would go on painting the old
# bytes; a name it has never seen has nothing to serve from.
ring_file() { # $1 = 0..100; $2 = stroke colour; prints the basename
  local name="ring-$1-${2#\#}.svg" tmp

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

# The elapsed fraction of a window is what the consumed fraction is worth reading against.
pace() { # $1 = label, $2 = used percentage, $3 = resets_at (0 = unknown), $4 = window seconds, $5 = now
  local elapsed diff
  (($3 > 0)) || return
  elapsed=$((($5 - ($3 - $4)) * 100 / $4))
  ((elapsed < 0 || elapsed > 100)) && return
  diff=$(($2 - elapsed))
  # The label and the figure sit in the columns row() uses, so the two blocks read as one table.
  if ((diff > 3)); then
    printf '%-7s %3d%% ahead of pace' "$1" "$diff"
  elif ((diff < -3)); then
    printf '%-7s %3d%% behind pace' "$1" $((-diff))
  else
    printf '%-7s %4s on pace' "$1" ''
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
  now=$(date +%s)
  maybe_refresh "$now"

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

  # resets_at is absolute, so a window whose reset has passed is empty again no matter how stale the
  # cache is. The next window's reset time is not derivable, hence the 0 rather than an extrapolation.
  ((fh_reset > 0 && now >= fh_reset)) && { fh_pct=0; fh_reset=0; }
  ((sd_reset > 0 && now >= sd_reset)) && { sd_pct=0; sd_reset=0; }

  # Everything visible is a CSS background image; the text only holds the space open.
  # An absent window gets no ring rather than an empty one, which would claim the quota is untouched.
  local tooltip='' paces='' pace_txt age age_txt maxpct=0 class=ok
  local -a pcts=()
  if ((fh_pct >= 0)); then
    pcts+=("$fh_pct")
    tooltip+=$(row '5 hour' "$fh_pct" "$fh_reset" "$now")
    pace_txt=$(pace '5 hour' "$fh_pct" "$fh_reset" "$FIVE_HOUR_WINDOW" "$now")
    [ -n "$pace_txt" ] && paces+=${paces:+$'\n'}$pace_txt
    ((fh_pct > maxpct)) && maxpct=$fh_pct
  fi
  if ((sd_pct >= 0)); then
    pcts+=("$sd_pct")
    [ -n "$tooltip" ] && tooltip+=$'\n'
    tooltip+=$(row 'Week' "$sd_pct" "$sd_reset" "$now")
    pace_txt=$(pace 'Week' "$sd_pct" "$sd_reset" "$SEVEN_DAY_WINDOW" "$now")
    [ -n "$pace_txt" ] && paces+=${paces:+$'\n'}$pace_txt
    ((sd_pct > maxpct)) && maxpct=$sd_pct
  fi

  age=$((now - updated))
  if ((age < 60)); then
    age_txt='just now'
  else
    age_txt="$(fmt_delta "$age") ago"
  fi
  tooltip+=$'\n\n'
  # A pace is a line of its own: appended to its row it would pass the width the tooltip wraps at.
  [ -n "$paces" ] && tooltip+="$paces"$'\n\n'
  tooltip+="updated $age_txt"

  ((maxpct >= 75)) && class=warn
  ((maxpct >= 90)) && class=crit

  write_style "$class" "${pcts[@]}"

  # The tooltip is its own GTK window, so #custom-claude-usage never reaches it and the columns only
  # line up if the markup asks for the monospace font itself.
  jq -cn --arg text "$(spacer "${#pcts[@]}")" --arg tt "<span font_family=\"JetBrainsMono Nerd Font\">$tooltip</span>" \
    --arg cls "$class" --argjson pct "$maxpct" \
    '{text: $text, class: $cls, tooltip: $tt, percentage: $pct}'
}

# Non-breaking, because Pango is free to drop ordinary spaces at an edge.
spacer() { # $1 = ring count
  local width=$((10 * (RING_X + ($1 - 1) * RING_PITCH + RING_SIZE + TRAIL))) n
  n=$(((width + SPACER_ADVANCE - 1) / SPACER_ADVANCE))
  printf '\u00a0%.0s' $(seq "$n")
}

join() { # $@ = CSS layer values; prints them as one comma-separated list
  local out=$1
  shift
  printf '%s' "$out" "${@/#/, }"
}

# The class only recolours the mascot, so the same three palette entries are resolved here for the
# rings. A wallpaper change rewrites the palette without telling us, so the colour is re-read every
# render and the rings catch up on the next interval.
write_style() { # $1 = class; $2.. = ring percentages
  local class=$1 fill css tmp pct name x=$RING_X
  shift
  case $class in
    crit) fill=$(palette error '#ffb4ab') ;;
    warn) fill=$(palette tertiary '#e5bad8') ;;
    *) fill=$(palette on_surface '#e3e1e9') ;;
  esac

  mkdir -p "$CACHE_DIR" || return

  local -a names=() images=() repeats=() positions=() sizes=()
  for pct in "$@"; do
    name=$(ring_file "$pct" "$fill") || return
    names+=("$name")
    images+=("url(\"$name\")")
    repeats+=("no-repeat")
    positions+=("${x}px center")
    sizes+=("${RING_SIZE}px ${RING_SIZE}px")
    x=$((x + RING_PITCH))
  done

  if ((${#images[@]})); then
    # url()s resolve against this file, so only the mark, which lives in the stow tree, needs a path.
    css="/* Generated by claude-usage.sh. */
#custom-claude-usage {
    background-image: url(\"$MARK\"), $(join "${images[@]}");
    background-repeat: no-repeat, $(join "${repeats[@]}");
    background-position: ${MARK_X}px center, $(join "${positions[@]}");
    background-size: ${MARK_SIZE}px ${MARK_SIZE}px, $(join "${sizes[@]}");
}"
  else
    css="/* Generated by claude-usage.sh: nothing to draw. */"
  fi

  # Waybar's reload_style_on_change watches this file and reloads the style provider alone, where
  # SIGUSR2 would reset the whole bar and every module on it would blink out and shift the layout.
  [ "$css" = "$(cat "$RINGS_CSS" 2>/dev/null)" ] && return
  tmp=$(mktemp "$CACHE_DIR/.rings.XXXXXX") || return
  if printf '%s\n' "$css" >"$tmp" && mv -f "$tmp" "$RINGS_CSS"; then
    local -a keep=()
    for name in "${names[@]}"; do keep+=(! -name "$name"); done
    find "$CACHE_DIR" -maxdepth 1 -name 'ring-*.svg' "${keep[@]}" -delete
  else
    rm -f "$tmp"
  fi
}

case "${1:-}" in
fetch) fetch ;;
*) render ;;
esac
