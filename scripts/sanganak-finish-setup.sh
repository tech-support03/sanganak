#!/usr/bin/env bash
# sanganak-finish-setup — the online half of a sanganak install.
#
# The ISO installs the core desktop offline. On the first login niri runs
# `sanganak-finish-setup --auto`, which opens this in a floating terminal and:
#
#   1. gets online — already connected (cable or Wi-Fi from the installer)
#      goes straight on; otherwise it offers a Wi-Fi picker (iwd) and carries
#      on by itself the moment a connection comes up
#   2. full system upgrade (the ISO's packages are as old as the ISO)
#   3. apps + gaming (packages/apps.txt, multilib) and GPU extras (NVIDIA)
#   4. AUR (packages/aur.txt) — each package on its own, failures only warn
#   5. board quirks that need the new packages (OpenRGB colour), fonts,
#      theme regeneration
#
# When everything succeeded it writes ~/.local/state/sanganak/setup-done and
# never opens again; if something failed it says what, and opens again next
# login. Run it any time (or from the menu) with --force.
#
#   sanganak-finish-setup           run now (in this terminal)
#   sanganak-finish-setup --auto    first-login hook: no-op once done
#   sanganak-finish-setup --force   run again even though it finished
set -uo pipefail

STATE="${XDG_STATE_HOME:-$HOME/.local/state}/sanganak"
DONE="$STATE/setup-done"
REPO="${SANGANAK_DIR:-$HOME/arch-setup}"
mkdir -p "$STATE"

case "${1:-}" in
    --auto)
        [[ -e "$DONE" ]] && exit 0
        # From niri's spawn-at-startup there is no terminal: open one.
        exec alacritty --class sanganak.update --title "Finish setup" -e "$0"
        ;;
    --force) rm -f "$DONE" ;;
esac

if [[ -z ${SANGANAK_SETUP_LOGGED:-} ]]; then
    exec env SANGANAK_SETUP_LOGGED=1 script -qefc "$(printf '%q ' "$0")" "$STATE/finish-setup.log"
fi

accent=$'\033[38;2;240;82;45m'; dim=$'\033[2m'; bold=$'\033[1m'; red=$'\033[1;31m'; green=$'\033[1;32m'; yellow=$'\033[1;33m'; off=$'\033[0m'
step() { printf '\n%s::%s %s%s%s\n' "$accent" "$off" "$bold" "$*" "$off"; }
warn() { printf '%s  !! %s%s\n' "$yellow" "$*" "$off"; FAILED+=("$*"); }
FAILED=()

[[ -f "$REPO/modules/lib.sh" ]] || { printf '%sCan'"'"'t find the sanganak repo at %s (set SANGANAK_DIR).%s\n' "$red" "$REPO" "$off"; read -rsn1; exit 1; }
source "$REPO/modules/lib.sh"

clear
[[ -f "$HOME/.config/fastfetch/sanganak-logo.ansi" ]] && cat "$HOME/.config/fastfetch/sanganak-logo.ansi"
printf '\n  %ssanganak — finish setup%s\n' "$bold" "$off"
printf '  %sApps, gaming, AUR packages and a full update. This needs the internet and takes a while.%s\n' "$dim" "$off"

# ---- 1. online -----------------------------------------------------------
online() { curl -fsS --max-time 5 -o /dev/null https://archlinux.org 2>/dev/null; }

wifi_dev() { iwctl device list 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | awk '$0 ~ /station/ {print $1; exit}'; }

pick_wifi() {
    local dev ssid pass
    dev="$(wifi_dev)"
    if [[ -z "$dev" ]]; then
        echo "No Wi-Fi adapter found. Plug in a network cable."
        return 1
    fi
    iwctl station "$dev" scan >/dev/null 2>&1; sleep 3
    mapfile -t nets < <(iwctl station "$dev" get-networks 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' \
        | awk 'NR>4 && NF>=2 { sub(/^[ >]+/, ""); n=$0; sub(/[ ]+(psk|open|8021x)[ ]+[*]+[ ]*$/, "", n); if (n != "") print n }')
    if (( ${#nets[@]} == 0 )); then echo "No networks found."; return 1; fi
    ssid="$(printf '%s\n' "${nets[@]}" | gum choose --header "Pick a Wi-Fi network")" || return 1
    pass="$(gum input --password --placeholder "Password for $ssid (empty for open / saved)")" || return 1
    if [[ -n "$pass" ]]; then iwctl --passphrase "$pass" station "$dev" connect "$ssid"
    else iwctl station "$dev" connect "$ssid"; fi
}

step "Getting online"
until online; do
    # --timeout returns to the online check every few seconds, so a cable
    # plugged in (or a slow DHCP) carries on without a key press.
    choice="$(gum choose --timeout 6s --header "You're offline. Connect to continue (this re-checks on its own)." \
              "Connect to Wi-Fi" "I plugged in a cable — check again" "Skip for now")" || choice="recheck"
    case "$choice" in
        "Connect to Wi-Fi") pick_wifi || true
                            for _ in $(seq 1 15); do online && break; sleep 1; done ;;
        "Skip for now")     printf '\nFinish setup will open again at your next login.\n'; read -rsn1 -p 'Press any key to close.'; exit 0 ;;
        *)                  sleep 1 ;;
    esac
done
echo "Online."

sudo -v || exit 1
( while kill -0 $$ 2>/dev/null; do sudo -n true; sleep 50; done ) 2>/dev/null &

# ---- 2. upgrade ------------------------------------------------------------
step "Updating mirrors and the system"
if command -v reflector >/dev/null; then
    sudo reflector --latest 12 --protocol https --sort rate --save /etc/pacman.d/mirrorlist >/dev/null 2>&1 || true
fi
enable_multilib
sudo pacman -Sy --needed --noconfirm archlinux-keyring || warn "keyring update failed"
sudo pacman -Syu --noconfirm || warn "system upgrade failed"

# ---- 3. apps + gaming -----------------------------------------------------
step "Installing apps and the gaming stack"
mapfile -t apps < <(read_list "$REPO/packages/apps.txt")
read -ra gpu <<<"$(gpu_extras) $(wifi_extras)"
if ! sudo pacman -S --needed --noconfirm "${apps[@]}" "${gpu[@]}"; then
    # One bad package fails the whole transaction; retry one by one so the
    # rest still lands and the failures are named.
    for p in "${apps[@]}" "${gpu[@]}"; do
        sudo pacman -S --needed --noconfirm "$p" >/dev/null 2>&1 || warn "couldn't install $p"
    done
fi

# ---- 4. AUR ----------------------------------------------------------------
step "Building AUR packages"
if command -v yay >/dev/null; then
    mapfile -t aur < <(read_list "$REPO/packages/aur.txt")
    for p in "${aur[@]}"; do
        printf '%s→ %s%s\n' "$dim" "$p" "$off"
        if ! yay -S --needed --noconfirm --sudoloop "$p"; then
            if [[ "$p" == apple-fonts ]]; then
                printf '%s  apple-fonts failed (Apple refreshed SF Pro; the AUR checksum lags). UI uses Noto Sans until it builds.%s\n' "$yellow" "$off"
            else
                warn "AUR package $p failed to build"
            fi
        fi
    done
else
    warn "yay is missing — AUR packages skipped"
fi

# ---- 5. finishing touches -----------------------------------------------------
step "Finishing touches"
# The board's RGB units were installed by the ISO but skip until openrgb exists.
if systemctl is-enabled rgb-color.service >/dev/null 2>&1; then
    sudo systemctl start rgb-color.service || warn "RGB colour didn't apply (check: sudo rgb-apply)"
fi
fc-cache -f >/dev/null 2>&1
command -v rice-theme >/dev/null && rice-theme set "$(rice-theme status 2>/dev/null || echo deccan)" >/dev/null 2>&1
xdg-user-dirs-update >/dev/null 2>&1 || true

echo
if (( ${#FAILED[@]} == 0 )); then
    touch "$DONE"
    printf '%sAll set. Enjoy sanganak.%s\n' "$green" "$off"
    if [[ ! -d /usr/lib/modules/$(uname -r) ]]; then
        printf 'The kernel was updated — reboot to finish.\n'
        gum confirm "Reboot now?" && systemctl reboot
    fi
else
    printf '%sFinished with problems:%s\n' "$yellow" "$off"
    printf '  • %s\n' "${FAILED[@]}"
    printf '\nThe log is %s. Finish setup opens again next login, or run it from the menu.\n' "$STATE/finish-setup.log"
fi
read -rsn1 -p 'Press any key to close.'
echo
