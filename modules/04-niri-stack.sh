#!/usr/bin/env bash
# 04-niri-stack.sh — make sure niri session, xdg-desktop-portal stack are present.
set -Eeuo pipefail

# The portal stack (gtk, gnome, wlr) is in packages/desktop.txt, installed by
# module 01 or the ISO's pacstrap; this module only registers the session.

log "Registering niri.desktop session for ly"
# Exec is sanganak-session (scripts/sanganak-session.sh): it explains a VM
# without 3D acceleration instead of a black screen, then runs niri-session.
sudo install -Dm644 /dev/stdin /usr/share/wayland-sessions/niri.desktop <<'EOF'
[Desktop Entry]
Name=Niri
Comment=Scrollable-tiling Wayland compositor
Exec=sanganak-session
Type=Application
EOF
# niri owns that file, so an upgrade would put Exec=niri-session back.
sudo install -Dm644 /dev/stdin /etc/pacman.d/hooks/sanganak-session.hook <<'EOF'
[Trigger]
Operation = Install
Operation = Upgrade
Type = Package
Target = niri

[Action]
Description = Pointing the Niri session at sanganak-session...
When = PostTransaction
Exec = /usr/bin/sed -i 's/^Exec=niri-session$/Exec=sanganak-session/' /usr/share/wayland-sessions/niri.desktop
EOF

ok "niri stack ready"
