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

AUR_PKGS=(
    niri
    nwg-displays
    kanshi
    xwayland-satellite
    # Side-bar dock apps not in the official repos. WhatsApp runs as a Chromium
    # web app (see scripts/whatsapp-web.sh) instead of the whatsapp-for-linux
    # AUR package, which is slow to build and lags upstream.
    spotify
)

log "Installing AUR packages with yay (this may take a while)"
yay -S --needed --noconfirm --sudoloop "${AUR_PKGS[@]}"

# SF Pro (system UI font). Installed on its own and non-fatal: the PKGBUILD
# pulls Apple's unversioned SF-Pro.dmg, so every time Apple refreshes it the
# checksum breaks until the AUR maintainer bumps it. That must not take the
# rest of the install down; fontconfig falls back to Noto Sans meanwhile and
# `yay -S apple-fonts` can be re-run later.
log "Installing SF Pro (apple-fonts, AUR)"
yay -S --needed --noconfirm --sudoloop apple-fonts \
    || warn "apple-fonts failed (likely an upstream checksum bump); UI uses Noto Sans until 'yay -S apple-fonts' succeeds"

ok "AUR packages installed"
