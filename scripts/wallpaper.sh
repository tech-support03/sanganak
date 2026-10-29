#!/usr/bin/env bash
# wallpaper — add, remove and pick the wallpapers in ~/Pictures/Wallpapers, the
# folder wallpaper-init, wallpaper-next and Mod+Shift+B cycle through.
#
#   wallpaper                     list them (● = on screen now)
#   wallpaper add [FILE|URL]...   copy images in (or download them) and show the
#                                 first. With nothing given, pick from the images
#                                 in ~/Downloads, ~/Pictures and ~/Desktop (fzf:
#                                 Tab marks several, or type a URL to download)
#   wallpaper rm [NAME]           move one to the Trash — by default the one on
#                                 screen, which then moves on to the next
#   wallpaper set NAME            show that one (a unique start of its name will do)
#   wallpaper open                open the folder in the file manager
#
# Images are jpg / jpeg / png / webp. Removed ones go to the Trash (gio), so a
# mistake is one restore away. The sanganak menu has Add / Remove / Folder, and
# under the wallpaper theme every change re-themes the rice (wallpaper-next).
set -Eeuo pipefail

WP_DIR="$HOME/Pictures/Wallpapers"
CURRENT_FILE="$HOME/.cache/wallpaper-current"
mkdir -p "$WP_DIR"

is_image() { [[ "${1,,}" =~ \.(jpe?g|png|webp)$ ]]; }
images()   { find "$WP_DIR" -maxdepth 1 -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) | sort; }
current()  { [[ -r "$CURRENT_FILE" ]] && head -n1 "$CURRENT_FILE" || true; }
say()      { echo "$*"; command -v notify-send >/dev/null && notify-send -t 2500 "Wallpaper" "$*" || true; }
die()      { echo "wallpaper: $*" >&2; command -v notify-send >/dev/null && notify-send -u low "Wallpaper" "$*" || true; exit 1; }

# NAME → its path in the folder (exact name, else a unique prefix).
resolve() {
    local n="${1##*/}" m
    [[ -f "$WP_DIR/$n" ]] && { echo "$WP_DIR/$n"; return; }
    mapfile -t m < <(images | while read -r f; do [[ "${f##*/}" == "$n"* ]] && echo "$f"; done)
    [[ ${#m[@]} -eq 1 ]] || die "${#m[@]} wallpapers match '$n'"
    echo "${m[0]}"
}

# A free name in the folder for NAME (photo.jpg → photo-2.jpg, …).
free_name() {
    local base="$1" stem ext n=2
    [[ -e "$WP_DIR/$base" ]] || { echo "$WP_DIR/$base"; return; }
    stem="${base%.*}"; ext="${base##*.}"
    while [[ -e "$WP_DIR/$stem-$n.$ext" ]]; do n=$((n + 1)); done
    echo "$WP_DIR/$stem-$n.$ext"
}

fetch() {   # URL → path of the downloaded image in the folder
    local url="$1" tmp type ext name
    tmp="$(mktemp)"
    type="$(curl -fsSL --retry 2 -o "$tmp" -w '%{content_type}' "$url")" || { rm -f "$tmp"; die "couldn't download $url"; }
    case "${type%%;*}" in
        image/jpeg) ext=jpg ;; image/png) ext=png ;; image/webp) ext=webp ;;
        *) rm -f "$tmp"; die "not a jpg/png/webp image: $url (${type:-unknown type})" ;;
    esac
    name="${url%%[?#]*}"; name="${name##*/}"; name="${name%.*}"
    name="$(tr -c 'A-Za-z0-9._-' '-' <<<"$name" | sed 's/-*$//; s/^-*//')"
    [[ -n "$name" ]] || name="wallpaper-$(date +%Y%m%d-%H%M%S)"
    local dest; dest="$(free_name "$name.$ext")"
    mv "$tmp" "$dest"; chmod 644 "$dest"
    echo "$dest"
}

pick() {    # interactive: images around the home folder, newest first, or a URL
    local out
    out="$(find "$HOME/Downloads" "$HOME/Pictures" "$HOME/Desktop" -maxdepth 3 -type f \
               \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) \
               -not -path "$WP_DIR/*" -printf '%T@ %p\n' 2>/dev/null | sort -rn | cut -d' ' -f2- |
           fzf --multi --print-query --reverse --prompt 'add wallpaper> ' \
               --header 'Enter: add · Tab: mark several · or paste an image URL and press Enter')" || true
    local query; query="$(head -n1 <<<"$out")"
    if [[ "$(wc -l <<<"$out")" -gt 1 ]]; then tail -n +2 <<<"$out"
    elif [[ "$query" =~ ^https?:// ]]; then echo "$query"
    fi
}

cmd_list() {
    local cur f; cur="$(current)"
    while read -r f; do
        [[ -n "$f" ]] || continue
        [[ "$f" == "$cur" ]] && printf '  ● %s\n' "${f##*/}" || printf '  ○ %s\n' "${f##*/}"
    done < <(images)
    echo "  ($WP_DIR)"
}

cmd_add() {
    local srcs=("$@") s dest first=""
    [[ ${#srcs[@]} -gt 0 ]] || mapfile -t srcs < <(pick)
    [[ ${#srcs[@]} -gt 0 && -n "${srcs[0]}" ]] || exit 0
    for s in "${srcs[@]}"; do
        if [[ "$s" =~ ^https?:// ]]; then
            dest="$(fetch "$s")"
        else
            [[ -f "$s" ]] || die "no such file: $s"
            is_image "$s" || die "not a jpg/png/webp image: $s"
            dest="$(free_name "${s##*/}")"
            cp "$s" "$dest"
        fi
        [[ -n "$first" ]] || first="$dest"
        echo "added ${dest##*/}"
    done
    wallpaper-next "$first"
    say "Added ${#srcs[@]} — now showing ${first##*/}"
}

cmd_rm() {
    local target next="" cur all i
    cur="$(current)"
    if [[ -n "${1:-}" ]]; then target="$(resolve "$1")"; else target="$cur"; fi
    [[ -n "$target" && -f "$target" ]] || die "nothing to remove (no wallpaper on screen)"
    mapfile -t all < <(images)
    [[ ${#all[@]} -gt 1 ]] || die "that's the only wallpaper — add another first"
    # Removing the one on screen: show the one after it (wrapping) instead.
    if [[ "$target" == "$cur" ]]; then
        for i in "${!all[@]}"; do [[ "${all[$i]}" == "$target" ]] && next="${all[$(( (i + 1) % ${#all[@]} ))]}"; done
    fi
    gio trash "$target" 2>/dev/null || rm -f "$target"
    [[ -n "$next" ]] && wallpaper-next "$next"
    say "Moved ${target##*/} to the Trash${next:+ — now showing ${next##*/}}"
}

case "${1:-list}" in
    list)   cmd_list ;;
    add)    shift; cmd_add "$@" ;;
    rm|remove) shift; cmd_rm "${1:-}" ;;
    set)    [[ -n "${2:-}" ]] || die "usage: wallpaper set NAME"; wallpaper-next "$(resolve "$2")" ;;
    open)   xdg-open "$WP_DIR" >/dev/null 2>&1 & disown ;;
    -h|--help) sed -n '2,19p' "$0" ;;
    *)      die "unknown command '$1' (list | add | rm | set | open)" ;;
esac
