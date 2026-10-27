#!/usr/bin/env bash
# Installed to /usr/local/bin/rgb-apply on the B650 EAGLE AX by modules/11-board-quirks.sh.
# Colour + effect control for the DDR5 RGB (ENE DRAM) and Gigabyte ARGB headers.
set -u

STATE=/etc/default/rgb-color
PRESETS=/etc/rgb-presets.conf
OPENRGB=/usr/bin/openrgb
MB="B650 EAGLE AX"
ARGB_SIZE=120

usage() {
    cat <<'USAGE'
rgb-apply NAME|RRGGBB [MODE] [SPEED]   set colour/mode/speed; remembered across reboots
rgb-apply                              reapply what is remembered (systemd units use this)
rgb-apply -l | --list                  list presets
rgb-apply -m | --modes                 list modes and how they map onto each device
rgb-apply --save NAME HEX [MODE] [SPEED]   add or update a preset
rgb-apply --count                      paint a repeating 5-colour pattern for counting LEDs
USAGE
}

# Logical mode -> DRAM mode, motherboard mode. "-" = no equivalent, use Static.
mode_map() {
    case "${1,,}" in
      static)      printf '%s\t%s' 'Static'         'Static' ;;
      breathing)   printf '%s\t%s' 'Breathing'      'Breathing' ;;
      flashing)    printf '%s\t%s' 'Flashing'       'Flashing' ;;
      doubleflash) printf '%s\t%s' 'Flashing'       'Double Flash' ;;
      cycle)       printf '%s\t%s' 'Spectrum Cycle' 'Color Cycle' ;;
      rainbow)     printf '%s\t%s' 'Rainbow'        'Color Cycle' ;;
      flicker)     printf '%s\t%s' 'Random Flicker' 'Random' ;;
      chase)       printf '%s\t%s' 'Chase'          '-' ;;
      chasefade)   printf '%s\t%s' 'Chase Fade'     '-' ;;
      *)           return 1 ;;
    esac
}
ALL_MODES='static breathing flashing doubleflash cycle rainbow flicker chase chasefade'

lookup() {   # preset name -> "HEX mode speed"
    awk -v want="${1,,}" '
        /^[[:space:]]*(#|$)/ { next }
        tolower($1) == want {
            gsub(/^#/, "", $2)
            m = ($3 == "" || $3 ~ /^#/) ? "static" : $3
            s = ($4 == "" || $4 ~ /^#/) ? ""       : $4
            print toupper($2), tolower(m), s; exit
        }' "$PRESETS" 2>/dev/null
}

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
  -l|--list)
    printf '%-12s %-8s %-12s %s\n' NAME HEX MODE SPEED
    awk '!/^[[:space:]]*(#|$)/ { m=($3==""||$3~/^#/)?"static":$3; s=($4==""||$4~/^#/)?"-":$4
          printf "%-12s %-8s %-12s %s\n", $1, toupper($2), tolower(m), s }' "$PRESETS"
    if [ -r "$STATE" ]; then . "$STATE" 2>/dev/null
       printf '\ncurrent: %s %s speed=%s\n' "${COLOR:-?}" "${MODE:-static}" "${SPEED:-default}"; fi
    exit 0 ;;
  -m|--modes)
    printf '%-12s %-16s %s\n' MODE DRAM MOTHERBOARD
    for m in $ALL_MODES; do
        IFS=$'\t' read -r d b <<<"$(mode_map "$m")"
        [ "$b" = "-" ] && b='(falls back to Static)'
        printf '%-12s %-16s %s\n' "$m" "$d" "$b"
    done
    exit 0 ;;
  --count)
    # Repeating red/green/blue/yellow/white so LEDs can be counted in groups of 5.
    pat=""; for ((i=0;i<ARGB_SIZE;i++)); do
        case $((i % 5)) in 0) c=FF0000;; 1) c=00FF00;; 2) c=0000FF;; 3) c=FFFF00;; 4) c=FFFFFF;; esac
        pat+="$c,"; done; pat="${pat%,}"
    for z in 0 1; do
        "$OPENRGB" --noautoconnect --device "$MB" --zone $z --size "$ARGB_SIZE" \
                   --mode direct --color "$pat" >/dev/null 2>&1
    done
    echo "Pattern applied: red, green, blue, yellow, white, repeating."
    echo "Count the groups of 5 along one fan to get its LED count."
    exit 0 ;;
  --save)
    [ $# -ge 3 ] || { echo "usage: rgb-apply --save NAME RRGGBB [MODE] [SPEED]" >&2; exit 1; }
    hex="${3#\#}"
    [[ "$hex" =~ ^[0-9A-Fa-f]{6}$ ]] || { echo "rgb-apply: '$3' is not a 6-digit hex colour" >&2; exit 1; }
    sm="${4:-static}"; sp="${5:-}"
    mode_map "$sm" >/dev/null || { echo "rgb-apply: unknown mode '$sm' (see --modes)" >&2; exit 1; }
    tmp=$(mktemp)
    awk -v n="${2,,}" '!(tolower($1) == n && $0 !~ /^[[:space:]]*#/)' "$PRESETS" > "$tmp"
    printf '%-13s %-8s %-12s %s\n' "${2,,}" "${hex^^}" "${sm,,}" "$sp" >> "$tmp"
    cat "$tmp" > "$PRESETS"; rm -f "$tmp"
    echo "rgb-apply: saved preset '${2,,}' = ${hex^^} ${sm,,} ${sp:-default}"
    exit 0 ;;
esac

if [ -n "${1:-}" ]; then
    stripped="${1#\#}"
    if [[ "$stripped" =~ ^[0-9A-Fa-f]{6}$ ]]; then
        COLOR="${stripped^^}"; MODE=static; SPEED=""
    else
        read -r COLOR MODE SPEED <<<"$(lookup "$1")" || true
        if [ -z "${COLOR:-}" ]; then
            echo "rgb-apply: '$1' is not a known preset or a 6-digit hex colour" >&2
            echo "try: rgb-apply --list" >&2; exit 1
        fi
    fi
    [ -n "${2:-}" ] && MODE="${2,,}"
    [ -n "${3:-}" ] && SPEED="$3"
    mode_map "$MODE" >/dev/null || { echo "rgb-apply: unknown mode '$MODE' (see --modes)" >&2; exit 1; }
    if [ -n "${SPEED:-}" ] && ! [[ "$SPEED" =~ ^([0-9]|[1-9][0-9]|100)$ ]]; then
        echo "rgb-apply: speed must be 0-100" >&2; exit 1; fi
    printf 'COLOR=%s\nMODE=%s\nSPEED=%s\n' "$COLOR" "$MODE" "${SPEED:-}" > "$STATE"
else
    [ -r "$STATE" ] && . "$STATE" 2>/dev/null
    COLOR="${COLOR:-8800FF}"; MODE="${MODE:-static}"; SPEED="${SPEED:-}"
fi

IFS=$'\t' read -r DRAM_MODE MB_MODE <<<"$(mode_map "$MODE")"
[ "$MB_MODE" = "-" ] && MB_MODE=Static

for _ in $(seq 1 30); do
    grep -qs PIIX4 /sys/class/i2c-dev/*/name && break
    sleep 1
done

# Modes vary in whether they accept a colour and whether they accept a speed,
# so try the richest form first and degrade rather than tracking each case.
apply_one() {
    local m="$1"; shift
    local -a sp=(); [ -n "${SPEED:-}" ] && sp=(--speed "$SPEED")
    "$OPENRGB" --noautoconnect "$@" --mode "$m" --color "$COLOR" "${sp[@]}" >/dev/null 2>&1 && return 0
    "$OPENRGB" --noautoconnect "$@" --mode "$m" "${sp[@]}"                  >/dev/null 2>&1 && return 0
    "$OPENRGB" --noautoconnect "$@" --mode "$m" --color "$COLOR"            >/dev/null 2>&1 && return 0
    "$OPENRGB" --noautoconnect "$@" --mode "$m"                             >/dev/null 2>&1
}

while read -r idx; do
    [ -n "$idx" ] && apply_one "$DRAM_MODE" --device "$idx"
done < <("$OPENRGB" --noautoconnect --list-devices 2>/dev/null \
         | grep -E '^[0-9]+: ENE DRAM' | cut -d: -f1)

apply_one "$MB_MODE" --device "$MB" --zone 0 --size "$ARGB_SIZE"
apply_one "$MB_MODE" --device "$MB" --zone 1 --size "$ARGB_SIZE"

echo "rgb-apply: $COLOR $MODE speed=${SPEED:-default} (dram=$DRAM_MODE mb=$MB_MODE)"
