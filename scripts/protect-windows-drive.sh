#!/usr/bin/env bash
# protect-windows-drive — make the Windows SSD physically invisible to the
# installer, without opening the case.
#
# WHY THIS EXISTS
#   This machine has TWO IDENTICAL Crucial CT1000P3PSSD8 1TB NVMe drives.
#   Same model string, same 931.5G size, same everything an installer shows you.
#   The ONLY reliable way to tell them apart is the serial number:
#
#       242849D4A723  →  WINDOWS   (ESP + MSR + 930.6G NTFS + recovery)
#       24504CC94939  →  LINUX     (the wipe target)
#
#   Kernel names (nvme0n1 / nvme1n1) are assigned in PCIe enumeration order and
#   are NOT guaranteed stable across boots or between kernels. Never pick a disk
#   by nvme name in the installer. This script keys off the serial only.
#
# WHAT IT DOES
#   1. Finds the Windows drive by serial, wherever it landed.
#   2. Refuses to continue if anything on it is mounted.
#   3. Marks every block node on it read-only  (blockdev --setro).
#   4. Unbinds its PCIe function from the nvme driver, which makes the device
#      node disappear outright. The installer cannot list, partition, format or
#      dd a device that has no /dev node. This is the software equivalent of
#      pulling the stick, and it is undone by a plain reboot.
#
# USAGE (run inside the live Arch/Omarchy installer, as root, BEFORE partitioning)
#       bash protect-windows-drive.sh          # arm the guard
#       bash protect-windows-drive.sh --status # just report, change nothing
#       bash protect-windows-drive.sh --undo   # rebind (or simply reboot)
#
set -uo pipefail

WIN_SERIAL="242849D4A723"
LNX_SERIAL="24504CC94939"

RED=$'\e[1;31m'; GRN=$'\e[1;32m'; YEL=$'\e[1;33m'; CYN=$'\e[1;36m'; RST=$'\e[0m'
die() { echo "${RED}FATAL:${RST} $*" >&2; exit 1; }

# Resolve a drive's kernel name from its serial. Empty if not present.
dev_by_serial() {
    local want="$1" d s
    for d in /sys/block/nvme*n1; do
        [ -e "$d" ] || continue
        s=$(cat "$d/device/serial" 2>/dev/null | tr -d ' ')
        [ "$s" = "$want" ] && { basename "$d"; return 0; }
    done
    return 1
}

# Resolve the PCI function (e.g. 0000:04:00.0) backing a given nvme device.
pci_of() {
    readlink -f "/sys/block/$1/device" 2>/dev/null \
        | grep -oE '[0-9a-f]{4}:[0-9a-f]{2}:[0-9a-f]{2}\.[0-9a-f]' | tail -1
}

report() {
    local w l
    w=$(dev_by_serial "$WIN_SERIAL") || w=""
    l=$(dev_by_serial "$LNX_SERIAL") || l=""
    echo
    echo "${CYN}── drive state ───────────────────────────────${RST}"
    if [ -n "$w" ]; then
        echo "  ${RED}WINDOWS  $WIN_SERIAL  → /dev/$w  ** VISIBLE **${RST}"
    else
        echo "  ${GRN}WINDOWS  $WIN_SERIAL  → hidden / not bound  ✓${RST}"
    fi
    if [ -n "$l" ]; then
        echo "  ${GRN}LINUX    $LNX_SERIAL  → /dev/$l  (install target)${RST}"
    else
        echo "  ${YEL}LINUX    $LNX_SERIAL  → NOT FOUND${RST}"
    fi
    echo "${CYN}──────────────────────────────────────────────${RST}"
    echo
}

case "${1:-}" in
--status)
    report; exit 0 ;;
--undo)
    # A bus rescan does NOT rebind a function that was explicitly unbound -- the
    # device is still enumerated, just driverless. Bind it back by hand: walk the
    # NVMe-class functions (0x0108xx) and bind any that currently have no driver.
    [ "$(id -u)" -eq 0 ] || die "run as root"
    found=0
    for d in /sys/bus/pci/devices/*/; do
        case "$(cat "$d/class" 2>/dev/null)" in 0x0108*) ;; *) continue ;; esac
        [ -e "$d/driver" ] && continue
        addr=$(basename "$d")
        if echo "$addr" > /sys/bus/pci/drivers/nvme/bind 2>/dev/null; then
            echo "  ${GRN}rebound $addr${RST}"; found=1
        else
            echo "  ${YEL}could not rebind $addr -- reboot to restore${RST}"
        fi
    done
    [ "$found" = 1 ] || echo "  no unbound NVMe functions found (nothing to undo)"
    sleep 2
    report; exit 0 ;;
esac

[ "$(id -u)" -eq 0 ] || die "run as root (sudo -i, then re-run)"

WIN_DEV=$(dev_by_serial "$WIN_SERIAL") || {
    echo "${GRN}Windows drive ($WIN_SERIAL) is already not visible. Nothing to do.${RST}"
    report; exit 0
}
LNX_DEV=$(dev_by_serial "$LNX_SERIAL") || \
    die "Linux target drive ($LNX_SERIAL) not found — stop and investigate before installing anything."

[ "$WIN_DEV" != "$LNX_DEV" ] || die "serial lookup collision — refusing to act"

echo
echo "Windows drive : /dev/$WIN_DEV  (serial $WIN_SERIAL)"
echo "Linux  target : /dev/$LNX_DEV  (serial $LNX_SERIAL)"

# Sanity check: the Windows drive must actually look like Windows. If this fails,
# the serial map is wrong and we must not touch anything.
if command -v lsblk >/dev/null 2>&1; then
    if ! lsblk -no FSTYPE "/dev/$WIN_DEV" 2>/dev/null | grep -qi ntfs; then
        die "/dev/$WIN_DEV has no NTFS partition — serial map looks wrong. Aborting."
    fi
fi

# Never operate on a drive with something mounted off it.
if mount | grep -q "/dev/$WIN_DEV"; then
    die "something on /dev/$WIN_DEV is mounted — unmount it first"
fi

PCI=$(pci_of "$WIN_DEV")
[ -n "$PCI" ] || die "could not resolve PCI address for /dev/$WIN_DEV"
echo "PCIe function : $PCI"
echo

# Layer 1 — read-only flag on every node of the drive.
for node in /dev/${WIN_DEV%n1}n*; do
    [ -b "$node" ] || continue
    blockdev --setro "$node" 2>/dev/null && echo "  ro  $node"
done

# Layer 2 — unbind from the nvme driver. The /dev node disappears.
if [ -e "/sys/bus/pci/drivers/nvme/$PCI" ]; then
    echo "$PCI" > /sys/bus/pci/drivers/nvme/unbind 2>/dev/null \
        && echo "  ${GRN}unbound $PCI from nvme driver${RST}" \
        || echo "  ${YEL}unbind failed — read-only flag still applies${RST}"
    sleep 1
fi

# Verify the drive really is gone.
if dev_by_serial "$WIN_SERIAL" >/dev/null; then
    echo
    echo "${RED}WARNING: the Windows drive is STILL VISIBLE.${RST}"
    echo "${RED}Do NOT proceed. Disable its M.2 slot in BIOS instead.${RST}"
    report; exit 1
fi

echo
echo "${GRN}✓ Windows drive is now invisible to this system.${RST}"
echo "  Only ${CYN}/dev/$LNX_DEV${RST} remains. That is your install target."
echo "  A reboot brings the Windows drive back, untouched."
report
