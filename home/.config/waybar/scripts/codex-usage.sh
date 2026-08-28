#!/usr/bin/env bash
# Waybar readout of the Codex rate limit windows.
#
#   codex-usage.sh        print one line of JSON for waybar (default)
#   codex-usage.sh fetch  ask OpenAI for the windows, cache them, signal waybar on change
#
# The shape mirrors claude-usage.sh next door, down to the generated ring stylesheet; read its
# comments for why the module draws with images and owns its own CSS. What differs is the source and
# the window count: a Codex plan exposes one or two windows and which lengths they are is the plan's
# business, so the rings and the tooltip are built from whatever the response carries.
set -uo pipefail

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/codex-usage"
CACHE="$CACHE_DIR/usage.json"

# The surface Codex itself reads for `/status`. Undocumented, so a shape change has to degrade
# rather than break: a failed fetch leaves the last cache on the bar with its age in the tooltip.
USAGE_URL="https://chatgpt.com/backend-api/wham/usage"
# The Codex CLI keeps this token fresh, so nothing here refreshes it.
CREDENTIALS="${CODEX_HOME:-$HOME/.codex}/auth.json"
REFRESH_INTERVAL=300
ATTEMPTED="$CACHE_DIR/last-fetch"

RINGS_CSS="$CACHE_DIR/rings.css"
MARK="$HOME/.config/waybar/openai.svg"
PALETTE="$HOME/.config/waybar/colors.css"
ARC_WIDTH=5
TRACK_OPACITY=0.45

# Geometry of the images painted over the label, in px at font-size 16px. The label's text is
# nothing but spaces, and their advance is the whole layout: a hit region follows text and not
# padding, so holding the width open with padding would leave the mark and the rings unhoverable.
# The mark needs no term in the width, since it sits inside the first ring's lead-in.
SPACER_ADVANCE=96 # tenths of a px, so the spacer count divides in integers
MARK_X=12
MARK_SIZE=18
RING_X=38
RING_SIZE=16
RING_PITCH=24
TRAIL=8 # right margin past the last ring

feed() { # usage JSON on stdin
  local new new_body old_body tmp
  new=$(jq -c '{updated_at: (now | floor), windows: (.windows // [])}') || return 1
  [ -n "$new" ] || return 1

  mkdir -p "$CACHE_DIR" || return 1
  new_body=$(jq -c 'del(.updated_at)' <<<"$new")
  old_body=$(jq -c 'del(.updated_at)' "$CACHE" 2>/dev/null)

  tmp=$(mktemp "$CACHE_DIR/.usage.XXXXXX") || return 1
  if ! printf '%s\n' "$new" >"$tmp" || ! mv -f "$tmp" "$CACHE"; then
    rm -f "$tmp"
    return 1
  fi

  # Most fetches come back identical, and a signal per fetch would re-exec the module for nothing.
  [ "$new_body" = "$old_body" ] || pkill -RTMIN+3 waybar
}

fetch() {
  local token account body payload
  token=$(jq -r '.tokens.access_token // empty' "$CREDENTIALS" 2>/dev/null)
  if [ -z "$token" ]; then
    echo "codex-usage: no access token in $CREDENTIALS" >&2
    return 1
  fi
  # Empty for a personal account; a workspace needs it to be told which account is asking.
  account=$(jq -r '.tokens.account_id // empty' "$CREDENTIALS" 2>/dev/null)

  body=$(curl -fsS --max-time 10 \
    -H "Authorization: Bearer $token" \
    ${account:+-H "chatgpt-account-id: $account"} \
    -H 'Content-Type: application/json' \
    "$USAGE_URL") || {
    echo "codex-usage: GET $USAGE_URL failed" >&2
    return 1
  }

  # reset_at is absolute and survives a stale cache, where reset_after_seconds would not; it is only
  # the fallback for a response that omits it. Identifying fields in the response are dropped here.
  payload=$(jq -c --argjson now "$(date +%s)" '
    def window($w):
      if ($w | type) == "object" and ($w.used_percent | type) == "number" then
        {used_percentage: $w.used_percent, window_seconds: ($w.limit_window_seconds // 0)}
        + (($w.reset_at // (if ($w.reset_after_seconds | type) == "number"
              then $now + $w.reset_after_seconds else null end))
           | if . == null then {} else {resets_at: .} end)
      else empty end;
    {windows: [window(.rate_limit.primary_window), window(.rate_limit.secondary_window)],
     plan: (.plan_type // ""),
     credits: (if .credits.unlimited == true or (.credits.has_credits == true)
               then {unlimited: (.credits.unlimited // false), balance: (.credits.balance // "0")}
               else null end)}
    | if .credits == null then del(.credits) else . end
  ' <<<"$body" 2>/dev/null) || return 1

  if [ "$(jq -r '.windows | length' <<<"$payload" 2>/dev/null)" = "0" ]; then
    echo "codex-usage: no usable windows in the response from $USAGE_URL" >&2
    return 1
  fi

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

# Progress runs along the rim rather than filling a wedge: a wedge tapers to nothing at the centre,
# so the low percentages that most of a quota's life is spent at read as less than they are.
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

# Which windows a plan gets is the plan's business, so the label is derived rather than assumed.
window_label() { # $1 = window length in seconds
  case $1 in
  604800) printf 'Week' ;;
  86400) printf 'Day' ;;
  0) printf 'Usage' ;;
  *)
    if (($1 % 86400 == 0)); then
      printf '%d day' $(($1 / 86400))
    elif (($1 % 3600 == 0)); then
      printf '%d hour' $(($1 / 3600))
    else
      printf '%d min' $(($1 / 60))
    fi
    ;;
  esac
}

# A window's length is reported, so the fraction of it that has elapsed is knowable and is what the
# fraction consumed is worth reading against.
pace() { # $1 = label, $2 = used percentage, $3 = resets_at (0 = unknown), $4 = window seconds, $5 = now
  local elapsed diff
  (($3 > 0 && $4 > 0)) || return
  elapsed=$((($5 - ($3 - $4)) * 100 / $4))
  ((elapsed < 0 || elapsed > 100)) && return
  diff=$(($2 - elapsed))
  printf '%s: ' "$1"
  if ((diff > 3)); then
    printf '%d%% ahead of pace' "$diff"
  elif ((diff < -3)); then
    printf '%d%% behind pace' $((-diff))
  else
    printf 'on pace'
  fi
}

# Every field is padded to its widest value ("Tue 14:00", "2d 12h") so the rows read as columns.
row() { # $1 = label, $2 = used percentage, $3 = resets_at (0 = unknown), $4 = now
  local line
  line=$(printf '%-7s %3d%% used, %3d%% left' "$1" "$2" $((100 - $2)))
  (($3 > 0)) && line+=$(printf '   resets %-9s  in %s' "$(clock_at "$3")" "$(fmt_delta $(($3 - $4)))")
  printf '%s' "$line"
}

render() {
  local updated now line pct reset window label
  now=$(date +%s)
  maybe_refresh "$now"

  [ -r "$CACHE" ] || hide
  updated=$(jq -r '.updated_at // 0' "$CACHE" 2>/dev/null) || hide
  [[ $updated =~ ^[0-9]+$ ]] || hide

  local -a pcts=() tooltip_rows=()
  local paces='' pace_txt maxpct=0 class=ok
  while IFS=$'\t' read -r pct reset window; do
    [ -n "$pct" ] || continue
    # resets_at is absolute, so a window whose reset has passed is empty again no matter how stale
    # the cache is. The next reset is not derivable, hence the 0 rather than an extrapolation.
    ((reset > 0 && now >= reset)) && { pct=0; reset=0; }
    label=$(window_label "$window")
    tooltip_rows+=("$(row "$label" "$pct" "$reset" "$now")")
    pcts+=("$pct")
    ((pct > maxpct)) && maxpct=$pct
    pace_txt=$(pace "$label" "$pct" "$reset" "$window" "$now")
    [ -n "$pace_txt" ] && paces+=${paces:+' · '}$pace_txt
  done < <(jq -r '.windows[]? | [(.used_percentage | round), (.resets_at // 0), (.window_seconds // 0)] | @tsv' "$CACHE" 2>/dev/null)

  ((${#pcts[@]})) || hide

  local credits
  credits=$(jq -r 'if .credits == null then "" elif .credits.unlimited then "unlimited credits" else "credits: " + .credits.balance end' "$CACHE" 2>/dev/null)

  local tooltip age age_txt
  tooltip=$(printf '%s\n' "${tooltip_rows[@]}")
  age=$((now - updated))
  if ((age < 60)); then
    age_txt='just now'
  else
    age_txt="$(fmt_delta "$age") ago"
  fi
  [ -n "$credits" ] && tooltip+=$'\n'"$credits"
  tooltip+=$'\n\n'
  # Each pace reads as a sentence, so they get their own line rather than a column in the rows above.
  [ -n "$paces" ] && tooltip+="$paces"$'\n'
  tooltip+="updated $age_txt"

  ((maxpct >= 75)) && class=warn
  ((maxpct >= 90)) && class=crit

  write_style "$class" "${pcts[@]}"

  # The tooltip is its own GTK window, so #custom-codex-usage never reaches it and the columns only
  # line up if the markup asks for the monospace font itself.
  jq -cn --arg text "$(spacer "${#pcts[@]}")" \
    --arg tt "<span font_family=\"JetBrainsMono Nerd Font\">$tooltip</span>" \
    --arg cls "$class" --argjson pct "$maxpct" \
    '{text: $text, class: $cls, tooltip: $tt, percentage: $pct}'
}

# The label is held open by its own text, so the spacer count is what reserves room for the images.
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

# The class only recolours the mark, so the same three palette entries are resolved here for the
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
    css="/* Generated by codex-usage.sh. */
#custom-codex-usage {
    background-image: url(\"$MARK\"), $(join "${images[@]}");
    background-repeat: no-repeat, $(join "${repeats[@]}");
    background-position: ${MARK_X}px center, $(join "${positions[@]}");
    background-size: ${MARK_SIZE}px ${MARK_SIZE}px, $(join "${sizes[@]}");
}"
  else
    css="/* Generated by codex-usage.sh: nothing to draw. */"
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
