#!/usr/bin/env bash
# 11-board-quirks.sh — per-motherboard fixes, keyed on the DMI board name.
#
# Gigabyte B650 EAGLE AX (the desktop): OpenRGB drives the DDR5 RGB and the
# ARGB fan headers, which needs two kernel-level workarounds:
#   - acpi_enforce_resources=lax on the kernel cmdline: the board's ACPI claims
#     the PIIX4 SMBus range (\GSA1.SMBI), so i2c-piix4 won't bind otherwise and
#     the RAM is invisible. (Limine already carries it — 06-bootloader-limine.sh;
#     this adds it for GRUB installs.)
#   - blacklist spd5118: it claims the DDR5 SPD hubs and blocks userspace access
#     (i2cdetect shows UU). Costs the DIMM temperature sensors.
# Then rgb-apply + presets + the boot/resume units, and a sudoers rule so the
# Quickshell RGB overlay (pc-rgb) can call rgb-apply without a password.
#
# Runs as root (chroot or sudo). A no-op on every other board.
set -Eeuo pipefail

BOARD="$(cat /sys/class/dmi/id/board_name 2>/dev/null || true)"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ "$BOARD" != "B650 EAGLE AX" ]]; then
    exit 0
fi
echo ">>> Board quirks: $BOARD (OpenRGB SMBus access)"

install -Dm644 /dev/stdin /etc/modprobe.d/blacklist-spd5118.conf <<'CONF'
# spd5118 binds the DDR5 SPD hubs at 0x50-0x57 and blocks userspace RGB access
# (i2cdetect shows "UU"). Tradeoff: no DIMM temperature sensors in hwmon.
# Revert by deleting this file + rebooting.
blacklist spd5118
CONF

if [[ -f /etc/default/grub ]] && ! grep -q 'acpi_enforce_resources=lax' /etc/default/grub; then
    sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"/GRUB_CMDLINE_LINUX_DEFAULT="\1 acpi_enforce_resources=lax"/' /etc/default/grub
    command -v grub-mkconfig >/dev/null && grub-mkconfig -o /boot/grub/grub.cfg >/dev/null
fi

install -Dm755 "$REPO/scripts/rgb-apply.sh" /usr/local/bin/rgb-apply
[[ -f /etc/rgb-presets.conf ]] || install -Dm644 "$REPO/dotfiles/rgb/rgb-presets.conf" /etc/rgb-presets.conf
install -Dm644 "$REPO/dotfiles/rgb/rgb-color.service" /etc/systemd/system/rgb-color.service
install -Dm644 "$REPO/dotfiles/rgb/rgb-color-resume.service" /etc/systemd/system/rgb-color-resume.service
# openrgb itself comes from apps.txt (online); the units only run once it exists.
systemctl enable rgb-color.service rgb-color-resume.service

install -Dm440 /dev/stdin /etc/sudoers.d/20-rgb-apply <<'CONF'
# The Quickshell RGB overlay (pc-rgb) sets the PC lighting without a password.
%wheel ALL=(root) NOPASSWD: /usr/local/bin/rgb-apply
CONF
visudo -cf /etc/sudoers.d/20-rgb-apply >/dev/null
