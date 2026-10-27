#!/usr/bin/env bash
# sanganak-pkg-install — fuzzy-pick official-repo packages to install.
# Tab multi-selects; the preview shows `pacman -Sii`. Installed packages are
# marked so you don't reinstall by accident.
set -uo pipefail

fzf_args=(
    --multi
    --prompt 'install › '
    --header 'Tab: select several · Enter: install · alt-p: toggle details · Esc: quit'
    --preview 'pacman -Sii {1}'
    --preview-window 'down:60%:wrap'
    --bind 'alt-p:toggle-preview'
    --bind 'alt-j:preview-down,alt-k:preview-up,alt-d:preview-half-page-down,alt-u:preview-half-page-up'
    --color 'pointer:#39d98a,marker:#39d98a,prompt:#39d98a,hl:#f0522d,hl+:#f0522d'
)
# "name  [installed]" — the marker is a second column fzf shows but {1} skips.
pkgs=$(pacman -Sl | awk '{print $2 ($4 == "[installed]" || $4 == "[installed:" ? "  [installed]" : "")}' \
        | fzf "${fzf_args[@]}" | awk '{print $1}')
[[ -n $pkgs ]] || exit 0

echo
mapfile -t list <<<"$pkgs"
sudo pacman -S --needed "${list[@]}"
status=$?
echo
if (( status == 0 )); then printf '\033[1;32mDone.\033[0m '; else printf '\033[1;31mpacman exited with %s.\033[0m ' "$status"; fi
read -rsn1 -p 'Press any key to close.'
