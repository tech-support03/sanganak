#!/usr/bin/env bash
# pc-rgb — the RGB overlay's verbs on top of rgb-apply.
#
#   pc-rgb static|breathing|flashing RRGGBB
#   pc-rgb rainbow
#   pc-rgb off
#
# Remembers the choice in ~/.config/OpenRGB/pc-rgb.conf (the overlay reads it
# back) and applies it through rgb-apply, which also persists it for boot and
# resume. rgb-apply runs as root through a sudoers rule scoped to that one
# command (written by modules/11-board-quirks.sh).
set -euo pipefail
command -v rgb-apply >/dev/null || { echo "pc-rgb: no rgb-apply on this machine" >&2; exit 1; }

mode="${1:-}"; hex="${2:-}"
case "$mode" in
    static|breathing|flashing) [[ "${hex#\#}" =~ ^[0-9A-Fa-f]{6}$ ]] || { echo "pc-rgb: $mode needs RRGGBB" >&2; exit 1; }
                               hex="${hex#\#}" ;;
    rainbow)                   hex="${hex:-FFFFFF}" ;;
    off)                       hex="000000" ;;
    *) echo "usage: pc-rgb static|breathing|flashing RRGGBB | rainbow | off" >&2; exit 1 ;;
esac

conf="$HOME/.config/OpenRGB/pc-rgb.conf"
mkdir -p "$(dirname "$conf")"
printf 'MODE=%s\nCOLOR=%s\n' "$mode" "${hex^^}" > "$conf"
[[ "$mode" == off ]] && mode=static
exec sudo -n /usr/local/bin/rgb-apply "$hex" "$mode"
