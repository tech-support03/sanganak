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
