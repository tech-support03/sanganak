#!/usr/bin/env bash
# 03-aur-packages.sh — AUR packages via yay.
set -Eeuo pipefail

# yay invokes gpg as the calling user to import maintainer signing keys.
# If $HOME is not writable or .gnupg is missing, the import dies with
# "can't create directory '$HOME/.gnupg': Permission denied". Heal that
# before yay touches anything.
if [[ ! -O "$HOME" ]] || [[ ! -w "$HOME" ]]; then
    sudo chown -R "$(id -u):$(id -g)" "$HOME"
fi
install -d -m 0700 "$HOME/.gnupg"
# A fresh gpg agent socket dir avoids stale socket errors after a chroot install.
install -d -m 0700 "${XDG_RUNTIME_DIR:-/tmp}/gnupg" 2>/dev/null || true

# packages/aur.txt. Each package builds on its own and a failure only warns:
# one broken PKGBUILD (apple-fonts breaks its checksum whenever Apple
# refreshes SF-Pro.dmg) must not take the rest of the install down.
# fontconfig falls back to Noto Sans until `yay -S apple-fonts` succeeds.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
mapfile -t AUR_PKGS < <(read_list "$(dirname "${BASH_SOURCE[0]}")/../packages/aur.txt")

log "Installing AUR packages with yay (this may take a while)"
for pkg in "${AUR_PKGS[@]}"; do
    yay -S --needed --noconfirm --sudoloop "$pkg" \
        || warn "$pkg failed to build; retry later with 'yay -S $pkg'"
done

ok "AUR packages installed"
