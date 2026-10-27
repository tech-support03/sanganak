#!/usr/bin/env bash
# sanganak-pkg-remove — fuzzy-pick explicitly installed packages to remove
# (pacman -Rns: also drops their now-unneeded dependencies and config backups).
set -uo pipefail

fzf_args=(
    --multi
    --prompt 'remove › '
    --header 'Tab: select several · Enter: remove · alt-p: toggle details · Esc: quit'
    --preview 'pacman -Qi {1}'
    --preview-window 'down:60%:wrap'
    --bind 'alt-p:toggle-preview'
    --bind 'alt-j:preview-down,alt-k:preview-up'
    --color 'pointer:#e87575,marker:#e87575,prompt:#e87575,hl:#f0522d,hl+:#f0522d'
)
pkgs=$(pacman -Qqe | fzf "${fzf_args[@]}")
[[ -n $pkgs ]] || exit 0

echo
mapfile -t list <<<"$pkgs"
sudo pacman -Rns "${list[@]}"
status=$?
echo
if (( status == 0 )); then printf '\033[1;32mDone.\033[0m '; else printf '\033[1;31mpacman exited with %s.\033[0m ' "$status"; fi
read -rsn1 -p 'Press any key to close.'
