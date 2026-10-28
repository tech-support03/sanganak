#!/usr/bin/env bash
# modules/lib.sh — helpers shared by the modules, the ISO chroot stage and
# sanganak-finish-setup. Source it; it defines functions only.

# Packages in a packages/*.txt list: one or more per line, # comments.
read_list() {
    sed 's/#.*//' "$1" | tr -s ' \t' '\n\n' | grep -v '^$'
}

# Turn on [multilib] in pacman.conf (steam, lib32 drivers). Idempotent.
# $1 = pacman.conf path (default /etc/pacman.conf).
enable_multilib() {
    local conf="${1:-/etc/pacman.conf}"
    grep -q '^\[multilib\]' "$conf" && return 0
    sudo sed -i '/^#\[multilib\]/,/^#Include/ s/^#//' "$conf"
    grep -q '^\[multilib\]' "$conf" || printf '\n[multilib]\nInclude = /etc/pacman.d/mirrorlist\n' | sudo tee -a "$conf" >/dev/null
}

# Hypervisor guest tools to enable for this machine (package already
# installed from desktop.txt). Echoes systemd units, empty on bare metal.
vm_guest_units() {
    case "$(systemd-detect-virt 2>/dev/null)" in
        kvm|qemu) echo "qemu-guest-agent.service spice-vdagentd.service" ;;
        vmware)   echo "vmtoolsd.service vmware-vmblock-fuse.service" ;;
        oracle)   echo "vboxservice.service" ;;
    esac
}

# Extra packages for the GPU(s) present: NVIDIA's open kernel module + its
# userspace (with 32-bit for Steam). AMD and Intel are covered by mesa /
# vulkan-radeon / vulkan-intel in desktop.txt + apps.txt.
gpu_extras() {
    if lspci -nn 2>/dev/null | grep -Ei 'vga|3d|display' | grep -qi nvidia; then
        echo "nvidia-open-dkms nvidia-utils lib32-nvidia-utils linux-headers"
    fi
}

# Broadcom Wi-Fi that only Broadcom's out-of-tree `wl` driver runs (the 2014
# MacBook Air's BCM4360 is 14e4:43a0); the open b43/brcmsmac drivers don't see
# it, so without this the machine has no Wi-Fi at all. Echoes the packages
# (DKMS build against the installed kernel's headers), empty otherwise.
wifi_extras() {
    local ids="4313 4328 4329 432a 432b 432c 432d 4353 4357 4358 4359 4365 43a0 43b1"
    local dev
    for dev in $(lspci -nn 2>/dev/null | grep -i 'network controller' | grep -o '14e4:[0-9a-f]\{4\}' | cut -d: -f2); do
        if [[ " $ids " == *" $dev "* ]]; then echo "broadcom-wl-dkms linux-headers dkms"; return; fi
    done
}
