#!/usr/bin/env bash
# 06-rice-chroot.sh — set the rice up for the new user, inside arch-chroot,
# with no network. Runs only for sanganak ISO installs (bootstrap.sh calls it
# when OFFLINE_CONF is set): the packages are already there from pacstrap, so
# this is the configuration half of install.sh — modules 00, 04, 07, 08, 09 run
# as the user with SANGANAK_CHROOT=1 (no --now, no downloads), 11 as root.
#
# Expects: TARGET_USERNAME, PROFILE, REPO (the repo copy inside the target),
# optional WALLPAPER_SRC. The online half is sanganak-finish-setup, which
# niri opens on the first login.
set -Eeuo pipefail

log()  { printf '\033[1;34m>>>\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m  ok\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m  !!\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m  XX\033[0m %s\n' "$*"; exit 1; }

: "${TARGET_USERNAME:?missing}"
: "${PROFILE:?missing}"
: "${REPO:?missing}"
U="$TARGET_USERNAME"
H="/home/$U"

# Modules call sudo for system files. For the length of this stage the user
# may do that without a password; the rule is removed on any exit.
SUDOERS=/etc/sudoers.d/99-sanganak-install
printf '%s ALL=(ALL:ALL) NOPASSWD: ALL\n' "$U" > "$SUDOERS"
chmod 440 "$SUDOERS"
trap 'rm -f "$SUDOERS"' EXIT

# Steam and the 32-bit drivers Finish setup installs live in multilib.
source "$REPO/modules/lib.sh"
sudo() { "$@"; }
enable_multilib /etc/pacman.conf
unset -f sudo

run_as_user() {
    local m="$1"
    log "module → $m"
    runuser -u "$U" -- env -i \
        HOME="$H" USER="$U" LOGNAME="$U" PATH="/usr/local/bin:/usr/bin:$H/.local/bin" \
        LANG="${LOCALE:-en_US.UTF-8}" TIMEZONE="${TIMEZONE:-}" \
        PROFILE="$PROFILE" SANGANAK_CHROOT=1 WALLPAPER_SRC="${WALLPAPER_SRC:-}" \
        ROOT_DIR="$REPO" MODULES_DIR="$REPO/modules" DOTFILES_DIR="$REPO/dotfiles" SCRIPTS_DIR="$REPO/scripts" \
        bash -c 'log(){ printf "\033[1;34m>>>\033[0m %s\n" "$*"; }; ok(){ printf "\033[1;32m  ok\033[0m %s\n" "$*"; }
                 warn(){ printf "\033[1;33m  !!\033[0m %s\n" "$*"; }; die(){ printf "\033[1;31m  XX\033[0m %s\n" "$*"; exit 1; }
                 export -f log ok warn die; cd "$HOME"; bash "$MODULES_DIR/$1"' _ "$m"
    ok "module → $m"
}

chown -R "$U:$U" "$REPO"
run_as_user 04-niri-stack.sh
run_as_user 00-display-config.sh
run_as_user 07-services.sh
run_as_user 08-link-dotfiles.sh
run_as_user 09-wallpapers.sh

log "module → 11-board-quirks.sh"
bash "$REPO/modules/11-board-quirks.sh"

log "Login shell → zsh"
chsh -s /usr/bin/zsh "$U" >/dev/null

# The ISO's live session doesn't know the target's hostname; ly reads it fresh.
ok "rice configured for $U (profile: $PROFILE) — Finish setup runs at first login"
