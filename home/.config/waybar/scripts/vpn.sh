#!/usr/bin/env bash
# Waybar module for NetworkManager's WireGuard and VPN connections.
# Without arguments it prints a line per NetworkManager change, so the pill follows connections toggled from anywhere, not just from the bar.
# With "toggle" it flips the only connection, or asks which one when there are several.

set -euo pipefail

icon="󰖂"

# One "state:name" line per profile, state empty while it is down.
# Name goes last because read hands it the rest of the line, colons included.
vpn_connections() {
    nmcli -t -e no -f TYPE,STATE,NAME connection show | while IFS=: read -r type state name; do
        case $type in
        wireguard | vpn) printf '%s:%s\n' "$state" "$name" ;;
        esac
    done
}

render() {
    local state name parts=() tooltip="" class="disconnected" pending=false

    while IFS=: read -r state name; do
        case $state in
        activated)
            parts+=("$name")
            tooltip+=$'\n'"$icon  $name"
            ;;
        activating | deactivating)
            parts+=("$name")
            tooltip+=$'\n'"$icon  $name ($state)"
            pending=true
            ;;
        *)
            tooltip+=$'\n'"     $name"
            ;;
        esac
    done < <(vpn_connections)

    # A machine without a VPN profile prints nothing, and hide-empty-text drops the module.
    if [ -z "$tooltip" ]; then
        jq -cn '{text: ""}'
        return
    fi

    local text="$icon"
    if [ ${#parts[@]} -gt 0 ]; then
        text+="  $(printf '%s, ' "${parts[@]}")"
        text=${text%, }
        class="connected"
    fi
    "$pending" && class="pending"

    jq -cn --arg text "$text" --arg tooltip "VPN${tooltip}"$'\n\n'"Click to toggle" --arg class "$class" \
        '{text: $text, tooltip: $tooltip, class: $class}'
}

toggle() {
    local states=() names=() state name choice

    while IFS=: read -r state name; do
        states+=("$state")
        names+=("$name")
    done < <(vpn_connections)

    case ${#names[@]} in
    0) return ;;
    1) choice=0 ;;
    *)
        choice=$(for i in "${!names[@]}"; do
            if [ -n "${states[i]}" ]; then
                printf '%s  %s\n' "$icon" "${names[i]}"
            else
                printf '     %s\n' "${names[i]}"
            fi
        done | rofi -dmenu -i -replace -p "VPN" -format i -config ~/.config/rofi/config-compact.rasi) || return 0
        ;;
    esac

    local verb=up
    [ -n "${states[choice]}" ] && verb=down

    # A failure here would otherwise vanish into waybar's log, leaving a click that seems to do nothing.
    local output
    if ! output=$(nmcli connection "$verb" id "${names[choice]}" 2>&1); then
        notify-send -a "vpn" -i "network-vpn-symbolic" "VPN ${names[choice]} failed to go $verb" "$output"
    fi
}

if [ "${1:-}" = "toggle" ]; then
    toggle
    exit 0
fi

last=""
while :; do
    current=$(render)
    if [ "$current" != "$last" ]; then
        printf '%s\n' "$current"
        last=$current
    fi
    # Waybar's death signal reaches only this script, so nmcli is given its own or it outlives the bar.
    read -r _ || break
done < <(setpriv --pdeathsig TERM nmcli monitor)
