#!/usr/bin/env bash
# iso/test-vm.sh — install the sanganak ISO into a QEMU VM and boot it.
#
#   iso/test-vm.sh install ISO   unattended install, no network (proves offline)
#   iso/test-vm.sh boot          boot the installed disk (network on)
#   iso/test-vm.sh shot FILE     screenshot the running VM (PNG)
#   iso/test-vm.sh keys TEXT…    type into the running VM (qemu sendkey names, e.g. ret, alt-tab)
#
# Options (env): VM_DIR (default /var/tmp/sanganak-vm), GL=0 for a plain
# virtio-vga without 3D (what a VM without GPU acceleration looks like),
# FIRMWARE=bios for legacy boot. Runs as your user; needs /dev/kvm, qemu,
# edk2-ovmf, mtools.
set -Eeuo pipefail

VM_DIR="${VM_DIR:-/var/tmp/sanganak-vm}"
DISK="$VM_DIR/disk.qcow2"
MON="$VM_DIR/monitor.sock"
mkdir -p "$VM_DIR"

firmware=()
if [[ "${FIRMWARE:-uefi}" == uefi ]]; then
    [[ -f "$VM_DIR/vars.fd" ]] || cp /usr/share/edk2/x64/OVMF_VARS.4m.fd "$VM_DIR/vars.fd"
    firmware=(-drive if=pflash,format=raw,readonly=on,file=/usr/share/edk2/x64/OVMF_CODE.4m.fd
              -drive if=pflash,format=raw,file="$VM_DIR/vars.fd")
fi
if [[ "${GL:-1}" == 1 ]]; then
    display=(-device virtio-vga-gl -display egl-headless)
else
    display=(-device virtio-vga -display none)
fi
common=(-enable-kvm -machine q35 -cpu host -smp 4 -m 6G "${firmware[@]}" "${display[@]}"
        -monitor unix:"$MON",server,nowait -device virtio-tablet -audiodev none,id=a -device intel-hda -device hda-duplex,audiodev=a)

monitor() { printf '%s\n' "$*" | socat - UNIX-CONNECT:"$MON" >/dev/null; }

case "${1:-}" in
    install)
        iso="${2:?usage: test-vm.sh install ISO}"
        rm -f "$DISK" "$VM_DIR/vars.fd"
        [[ "${FIRMWARE:-uefi}" == uefi ]] && cp /usr/share/edk2/x64/OVMF_VARS.4m.fd "$VM_DIR/vars.fd"
        qemu-img create -q -f qcow2 "$DISK" 40G
        # Answers for sanganak-installer on a small FAT drive labelled SANGANAK_AUTO.
        auto="$VM_DIR/auto.img"
        rm -f "$auto"; truncate -s 4M "$auto"; mkfs.fat -n SANGANAK_AUTO "$auto" >/dev/null
        cat > "$VM_DIR/sanganak-auto.conf" <<'CONF'
DISK=/dev/vda
USERNAME=tester
PASSWORD=sanganak
HOSTNAME=sanganak-vm
TIMEZONE=America/Los_Angeles
PROFILE=vm
AUTO_CONFIRM=yes
CONF
        mcopy -i "$auto" "$VM_DIR/sanganak-auto.conf" ::/
        echo "Installing (no network). The VM powers off when done; watch with: $0 shot FILE"
        qemu-system-x86_64 "${common[@]}" -nic none \
            -drive file="$DISK",if=virtio,format=qcow2 \
            -drive file="$auto",if=virtio,format=raw \
            -cdrom "$iso" -boot d
        ;;
    boot)
        qemu-system-x86_64 "${common[@]}" -nic user,model=virtio-net-pci \
            -drive file="$DISK",if=virtio,format=qcow2
        ;;
    shot)
        out="${2:?usage: test-vm.sh shot FILE.png}"
        monitor "screendump $VM_DIR/shot.ppm"
        sleep 1; magick "$VM_DIR/shot.ppm" "$out"
        ;;
    keys)
        shift
        for k in "$@"; do monitor "sendkey $k"; sleep 0.08; done
        ;;
    *) sed -n '2,13p' "$0"; exit 2 ;;
esac
