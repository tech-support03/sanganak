#!/usr/bin/env bash
# fastfetch-popup — small floating alacritty window running fastfetch. Sized
# for the builtin Arch logo (37×19) plus the module column.
set -Eeuo pipefail

exec alacritty \
    --class fastfetch-popup \
    --title "System Summary" \
    -o "window.dimensions.columns=92" \
    -o "window.dimensions.lines=22" \
    -o "window.padding.x=14" \
    -o "window.padding.y=12" \
    -e sh -c 'fastfetch; printf "\nPress any key to close..."; read -n1'
