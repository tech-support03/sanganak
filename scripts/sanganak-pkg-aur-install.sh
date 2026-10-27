#!/usr/bin/env bash
# sanganak-pkg-aur-install — fuzzy-pick AUR packages to build and install
# with yay. alt-b shows the PKGBUILD — read it before installing anything
# from the AUR.
set -uo pipefail
command -v yay >/dev/null || { echo "yay is not installed (run sanganak-finish-setup)."; read -rsn1; exit 1; }

fzf_args=(
    --multi
    --prompt 'aur › '
    --header 'Tab: select several · Enter: install · alt-b: PKGBUILD · alt-i: info · Esc: quit'
    --preview 'yay -Siia {1}'
    --preview-window 'down:60%:wrap'
    --bind 'alt-b:change-preview:yay -Gpa {1} | tail -n +5'
    --bind 'alt-i:change-preview:yay -Siia {1}'
    --bind 'alt-j:preview-down,alt-k:preview-up,alt-d:preview-half-page-down,alt-u:preview-half-page-up'
    --color 'pointer:#39d98a,marker:#39d98a,prompt:#39d98a,hl:#f0522d,hl+:#f0522d'
)
echo "Loading the AUR package list…"
pkgs=$(yay -Slqa | fzf "${fzf_args[@]}")
[[ -n $pkgs ]] || exit 0

echo
mapfile -t list <<<"$pkgs"
yay -S --needed "${list[@]/#/aur/}"
status=$?
echo
if (( status == 0 )); then printf '\033[1;32mDone.\033[0m '; else printf '\033[1;31myay exited with %s.\033[0m ' "$status"; fi
read -rsn1 -p 'Press any key to close.'
