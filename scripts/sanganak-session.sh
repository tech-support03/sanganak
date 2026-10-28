#!/usr/bin/env bash
# sanganak-session — what ly starts for the "Niri" session (niri.desktop's
# Exec, set by modules/04-niri-stack.sh and kept by a pacman hook).
#
# niri renders only on a hardware GPU (or a VM's virtual 3D GPU); it skips
# Mesa's software renderer, so in a VM without 3D acceleration it starts with
# no outputs and the screen just stays black. Catch that case here and say
# what to change instead, then start niri the normal way.
virt="$(systemd-detect-virt 2>/dev/null || echo none)"
no_3d=""
if [[ "$virt" != none ]]; then
    if ! compgen -G '/dev/dri/renderD*' >/dev/null; then
        no_3d="this virtual GPU has no 3D support at all"
    elif journalctl -k -b -q -g 'features: -virgl' 2>/dev/null | grep -q .; then
        no_3d="the virtio GPU runs without virgl (3D off)"
    fi
fi

if [[ -n "$no_3d" ]]; then
    clear
    cat <<MSG

  sanganak can't start its desktop in this virtual machine:
  $no_3d, and niri needs GPU acceleration.

  Turn on 3D acceleration for the VM, then reboot:
    • QEMU / virt-manager   Video: Virtio with "3D acceleration" + Display: Spice/GTK with OpenGL
                            (qemu: -device virtio-vga-gl -display gtk,gl=on)
    • VirtualBox            Display → Graphics Controller VMSVGA, "Enable 3D Acceleration"
    • VMware                Display → "Accelerate 3D graphics"
    • Hyper-V               has no 3D for Linux guests — use one of the above

  You can still use this machine from the console (Ctrl+Alt+F2).

MSG
    read -rsn1 -p "  Press any key to return to the login screen." </dev/tty
    exit 1
fi

exec niri-session
