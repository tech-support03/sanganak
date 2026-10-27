#!/usr/bin/env bash
# sanganak-update — update the whole system, Omarchy-update style.
#
#   1. show what's pending (repo + AUR) and ask
#   2. archlinux-keyring first, so a stale keyring never fails the upgrade
#   3. pacman -Syu, then AUR (yay -Sua), then firmware metadata if fwupd exists
#   4. offer to remove orphans, list new .pacnew files
#   5. offer a reboot when the running kernel was replaced
#
# The whole run is logged to ~/.local/state/sanganak/update.log.
#   sanganak-update -y   no questions (orphans kept, no reboot)
set -Eeuo pipefail

LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/sanganak"
mkdir -p "$LOG_DIR"
if [[ -z ${SANGANAK_UPDATE_LOGGED:-} ]]; then
    exec env SANGANAK_UPDATE_LOGGED=1 script -qefc "$(printf '%q ' "$0" "$@")" "$LOG_DIR/update.log"
fi

YES=false
[[ ${1:-} == "-y" ]] && YES=true
accent=$'\033[38;2;240;82;45m'; dim=$'\033[2m'; bold=$'\033[1m'; red=$'\033[1;31m'; green=$'\033[1;32m'; off=$'\033[0m'
step() { printf '\n%s::%s %s%s%s\n' "$accent" "$off" "$bold" "$*" "$off"; }
ask()  { $YES && return 0; if command -v gum >/dev/null; then gum confirm "$1"; else read -rp "$1 [Y/n] " a; [[ ${a,,} != n* ]]; fi; }
finish() {
    local code=$?
    echo
    if (( code == 0 )); then printf '%sUpdate finished.%s ' "$green" "$off"
    else printf '%sThe update stopped (exit %s). The log is %s.%s ' "$red" "$code" "$LOG_DIR/update.log" "$off"; fi
    $YES || read -rsn1 -p 'Press any key to close.'
    echo
}
trap finish EXIT

# Free space: an upgrade that runs out of room half-way is the worst case.
avail=$(df --output=avail -k / | tail -1)
if (( avail < 2 * 1024 * 1024 )); then
    printf '%sLess than 2 GB free on /. Free some space first (paccache -rk1 clears old packages).%s\n' "$red" "$off"
    exit 1
fi

step "Checking for updates"
repo=$(checkupdates 2>/dev/null || true)
aur=$(command -v yay >/dev/null && yay -Qua 2>/dev/null || true)
nrepo=$(grep -c . <<<"$repo" || true); naur=$(grep -c . <<<"$aur" || true)
if (( nrepo + naur == 0 )); then
    echo "Everything is up to date."
    exit 0
fi
[[ -n $repo ]] && { printf '%s%s from the repos:%s\n' "$bold" "$nrepo" "$off"; sed 's/^/  /' <<<"$repo" | column -t; }
[[ -n $aur  ]] && { printf '\n%s%s from the AUR:%s\n' "$bold" "$naur" "$off"; sed 's/^/  /' <<<"$aur" | column -t; }
echo
ask "Update $((nrepo + naur)) packages?" || exit 0

sudo -v
# Keep sudo alive for the AUR builds, which can outlast the timestamp.
( while kill -0 $$ 2>/dev/null; do sudo -n true; sleep 50; done ) 2>/dev/null &

running_kernel=$(uname -r)
if (( nrepo > 0 )); then
    if grep -q '^archlinux-keyring ' <<<"$repo"; then
        step "Updating the keyring first"
        sudo pacman -Sy --needed --noconfirm archlinux-keyring
    fi
    step "Updating system packages"
    sudo pacman -Syu --noconfirm
fi
if (( naur > 0 )); then
    step "Updating AUR packages"
    yay -Sua --noconfirm --sudoloop || printf '%sSome AUR packages failed to build; the rest of the system is updated.%s\n' "$red" "$off"
fi
if command -v fwupdmgr >/dev/null; then
    step "Refreshing firmware metadata"
    fwupdmgr refresh --force >/dev/null 2>&1 || true
    fwupdmgr get-updates 2>/dev/null | grep -q 'Upgrade' && echo "Firmware updates are available: run 'fwupdmgr update'."
fi

orphans=$(pacman -Qdtq 2>/dev/null || true)
if [[ -n $orphans ]] && ! $YES; then
    step "Orphaned packages"
    sed 's/^/  /' <<<"$orphans"
    if ask "Remove these $(grep -c . <<<"$orphans") orphans?"; then
        mapfile -t o <<<"$orphans"; sudo pacman -Rns --noconfirm "${o[@]}"
    fi
fi

pacnew=$(find /etc -name '*.pacnew' 2>/dev/null || true)
if [[ -n $pacnew ]]; then
    step "Config files with new versions (.pacnew) — merge these by hand"
    sed 's/^/  /' <<<"$pacnew"
fi

# The old kernel's modules are gone once it's replaced, so new hardware or
# a module load would fail until a reboot.
if [[ ! -d /usr/lib/modules/$running_kernel ]]; then
    step "The kernel was updated"
    printf '%sReboot to finish the update.%s\n' "$dim" "$off"
    if ! $YES && ask "Reboot now?"; then trap - EXIT; systemctl reboot; fi
fi
