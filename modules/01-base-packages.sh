#!/usr/bin/env bash
# 01-base-packages.sh — official repo packages (idempotent).
set -Eeuo pipefail

# Lists live in packages/ (shared with the ISO and sanganak-finish-setup):
# desktop.txt is the core session, apps.txt the apps + gaming stack.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
PKG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../packages" && pwd)"
mapfile -t PKGS_CORE < <(read_list "$PKG_DIR/desktop.txt"; read_list "$PKG_DIR/apps.txt")
read -ra GPU_PKGS <<<"$(gpu_extras)"
PKGS_CORE+=("${GPU_PKGS[@]}")

PKGS_BAREMETAL=(
    intel-ucode amd-ucode
)

# steam and the lib32 drivers live in multilib.
log "Enabling [multilib]"
enable_multilib

log "Refreshing pacman databases"
sudo pacman -Syu --noconfirm --needed

log "Installing core packages"
sudo pacman -S --needed --noconfirm "${PKGS_CORE[@]}"

if [[ "$PROFILE" != "vm" ]]; then
    log "Installing microcode (bare-metal profile: $PROFILE)"
    sudo pacman -S --needed --noconfirm "${PKGS_BAREMETAL[@]}" || true
fi

ok "base packages installed"
