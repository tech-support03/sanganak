#!/usr/bin/env bash
# 04-niri-stack.sh — make sure niri session, xdg-desktop-portal stack are present.
set -Eeuo pipefail

# The portal stack (gtk, gnome, wlr) is in packages/desktop.txt, installed by
# module 01 or the ISO's pacstrap; this module only registers the session.

log "Registering niri.desktop session for greetd/SDDM/GDM"
sudo install -Dm644 /dev/stdin /usr/share/wayland-sessions/niri.desktop <<'EOF'
[Desktop Entry]
Name=Niri
Comment=Scrollable-tiling Wayland compositor
Exec=niri-session
Type=Application
EOF

ok "niri stack ready"
