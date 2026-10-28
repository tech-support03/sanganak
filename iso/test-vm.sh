#!/usr/bin/env bash
# iso/test-vm.sh — install the sanganak ISO into a QEMU VM and boot it.
#
#   iso/test-vm.sh install ISO   unattended install, no network (proves offline)
#   iso/test-vm.sh boot          boot the installed disk (network on)
#   iso/test-vm.sh shot FILE     screenshot the running VM (PNG)
#   iso/test-vm.sh keys KEY…     send keys to the VM (qemu sendkey names, e.g. ret, ctrl-alt-f2)
#   iso/test-vm.sh type TEXT     type a line of text, then Enter
#
# Options (env): VM_DIR (default /var/tmp/sanganak-vm), GL=0 for a plain
# virtio-vga without 3D (what a VM without GPU acceleration looks like),
# FIRMWARE=bios for legacy boot. Runs as your user; needs /dev/kvm, qemu,
# edk2-ovmf, e2fsprogs, socat.
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
    # A visible GTK window: with egl-headless, screendump only ever returns
    # the pre-KMS frame, so the GL session is captured from the window.
    display=(-device virtio-vga-gl -display gtk,gl=on,show-menubar=off)
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
        # Answers for sanganak-installer on a small drive labelled SANGANAK_AUTO.
        auto="$VM_DIR/auto.img"
        # ext4, not FAT: FAT labels stop at 11 characters. mke2fs -d fills it
        # without root.
        rm -rf "$auto" "$VM_DIR/auto"; mkdir -p "$VM_DIR/auto"
        cat > "$VM_DIR/auto/sanganak-auto.conf" <<'CONF'
DISK=/dev/vda
USERNAME=tester
PASSWORD=sanganak
HOSTNAME=sanganak-vm
TIMEZONE=America/Los_Angeles
PROFILE=vm
AUTO_CONFIRM=yes
CONF
        mke2fs -q -t ext4 -L SANGANAK_AUTO -d "$VM_DIR/auto" "$auto" 8M
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
        if [[ "${GL:-1}" == 1 ]] && command -v hyprctl >/dev/null; then
            geo="$(hyprctl clients -j | jq -r '.[] | select(.class|test("qemu";"i")) | "\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])"' | head -n1)"
            grim -g "$geo" "$out"
        else
            monitor "screendump $VM_DIR/shot.ppm"
            sleep 1; magick "$VM_DIR/shot.ppm" "$out"
        fi
        ;;
    keys)
        shift
        for k in "$@"; do monitor "sendkey $k"; sleep 0.08; done
        ;;
    type)
        python3 -I - "${2:?usage: test-vm.sh type TEXT}" <<'PY' | while read -r k; do monitor "sendkey $k"; sleep 0.04; done
import sys
named = {" ": "spc", "-": "minus", "=": "equal", "/": "slash", ".": "dot", ",": "comma",
         ";": "semicolon", "'": "apostrophe", "\\": "backslash", "[": "bracket_left",
         "]": "bracket_right", "`": "grave_accent"}
shifted = {"|": "backslash", "_": "minus", "+": "equal", "?": "slash", ">": "dot", "<": "comma",
           ":": "semicolon", '"': "apostrophe", "{": "bracket_left", "}": "bracket_right", "~": "grave_accent",
           "!": "1", "@": "2", "#": "3", "$": "4", "%": "5", "^": "6", "&": "7", "*": "8", "(": "9", ")": "0"}
for c in sys.argv[1]:
    if c in shifted: print("shift-" + shifted[c])
    elif c in named: print(named[c])
    elif c.isupper(): print("shift-" + c.lower())
    else: print(c)
print("ret")
PY
        ;;
    *) sed -n '2,14p' "$0"; exit 2 ;;
esac
