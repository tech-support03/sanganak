#!/usr/bin/env bash
# iso/build.sh — build the sanganak installer ISO.
#
#   sudo iso/build.sh [--out DIR] [--work DIR] [--wallpapers DIR] [--keep-work]
#
# Modelled on the Omarchy ISO: archiso's releng profile + a bundled offline
# pacman repo + a gum configurator that starts on tty1. The repo holds the
# base system (every bootloader / laptop / USB variant bootstrap.sh can pick),
# packages/desktop.txt and the prebuilt AUR helper (packages/aur-offline.txt),
# with all their dependencies — so the core desktop installs with no network.
# Apps, gaming and the rest come later from sanganak-finish-setup.
#
# Needs: archiso, git, and a sudo-capable normal user (makepkg won't run as
# root) — run it with sudo from your login. Output: DIR/sanganak-YYYY.MM.DD-x86_64.iso
set -Eeuo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$REPO/out"
WORK="/var/tmp/sanganak-iso"
WALLPAPERS=""
KEEP_WORK=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --out) OUT="$2"; shift 2 ;;
        --work) WORK="$2"; shift 2 ;;
        --wallpapers) WALLPAPERS="$2"; shift 2 ;;
        --keep-work) KEEP_WORK=true; shift ;;
        -h|--help) sed -n '2,16p' "$0"; exit 0 ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
done

log() { printf '\033[1;34m>>>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m  XX\033[0m %s\n' "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "run with sudo: sudo iso/build.sh"
[[ -n "${SUDO_USER:-}" && "$SUDO_USER" != root ]] || die "run via sudo from a normal user (makepkg can't build as root)"
command -v mkarchiso >/dev/null || die "archiso is not installed (pacman -S archiso)"
RELENG=/usr/share/archiso/configs/releng
[[ -d $RELENG ]] || die "missing $RELENG"
source "$REPO/modules/lib.sh"

PROFILE_DIR="$WORK/profile"
OFFLINE="$PROFILE_DIR/airootfs/var/cache/sanganak/offline"
rm -rf "$PROFILE_DIR" "$WORK/build"
mkdir -p "$WORK" "$OUT"

# ---- 1. profile: releng + our overlay ---------------------------------------
log "Assembling the archiso profile"
cp -a "$RELENG/." "$PROFILE_DIR/"
cp -a "$REPO/iso/airootfs/." "$PROFILE_DIR/airootfs/"
# Extra live-environment packages: gum for the configurator, python for the logo.
printf '%s\n' gum python >> "$PROFILE_DIR/packages.x86_64"

sed -i \
    -e 's/^iso_name=.*/iso_name="sanganak"/' \
    -e 's/^iso_label=.*/iso_label="SANGANAK_$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y%m)"/' \
    -e 's|^iso_publisher=.*|iso_publisher="sanganak <https://github.com/tech-support03/sanganak>"|' \
    -e 's/^iso_application=.*/iso_application="sanganak installer"/' \
    "$PROFILE_DIR/profiledef.sh"
# zstd instead of xz (the live root is read cold on every boot), and the
# offline repo stored uncompressed: its packages are already zstd.
sed -i "s|^airootfs_image_tool_options=.*|airootfs_image_tool_options=('-comp' 'zstd' '-Xcompression-level' '15' '-b' '1M' '-action' 'uncompressed@subpathname(var/cache/sanganak/offline)')|" \
    "$PROFILE_DIR/profiledef.sh"
cat >> "$PROFILE_DIR/profiledef.sh" <<'DEF'
file_permissions+=(
  ["/usr/local/bin/sanganak-installer"]="0:0:755"
  ["/root/sanganak"]="0:0:755"
)
DEF
# Boot menu titles.
grep -rl 'Arch Linux install medium' "$PROFILE_DIR"/{efiboot,syslinux,grub} 2>/dev/null \
    | xargs -r sed -i 's/Arch Linux install medium/sanganak installer/g'

# ---- 2. offline repo ----------------------------------------------------------
log "Downloading the offline package set (with every dependency)"
mkdir -p "$OFFLINE" "$WORK/db"
# A fresh dbpath makes pacman treat nothing as installed, so -Sw fetches the
# complete dependency closure rather than only what this host lacks.
# Official Arch mirrors, whatever this host uses (an Omarchy host points at
# Omarchy's lagging snapshot mirror). Both the offline repo and the live
# environment come from these.
cat > "$WORK/mirrorlist" <<'MIRRORS'
Server = https://geo.mirror.pkgbuild.com/$repo/os/$arch
Server = https://fastly.mirror.pkgbuild.com/$repo/os/$arch
Server = https://mirror.rackspace.com/archlinux/$repo/os/$arch
MIRRORS
sed -i "s|^Include = /etc/pacman.d/mirrorlist|Include = $WORK/mirrorlist|" "$PROFILE_DIR/pacman.conf"
cat > "$WORK/pacman-build.conf" <<CONF
[options]
Architecture = auto
ParallelDownloads = 8
SigLevel = Required DatabaseOptional
[core]
Include = $WORK/mirrorlist
[extra]
Include = $WORK/mirrorlist
[multilib]
Include = $WORK/mirrorlist
CONF
# Everything iso-stage/03-pacstrap.sh may ask for, across all its branches,
# plus what the bootloader modules install inside the chroot.
BASE=(base base-devel linux linux-firmware mkinitcpio sudo git vim iwd e2fsprogs dosfstools
      pciutils usbutils man-db man-pages bash-completion intel-ucode amd-ucode
      grub efibootmgr os-prober mtools sbsigntools mokutil limine sbctl dkms linux-headers
      tlp tlp-rdw acpi acpid upower brightnessctl bluez bluez-utils wpa_supplicant iio-sensor-proxy
      broadcom-wl-dkms)
mapfile -t DESKTOP < <(read_list "$REPO/packages/desktop.txt")
pacman --config "$WORK/pacman-build.conf" --dbpath "$WORK/db" -Sy >/dev/null
pacman --config "$WORK/pacman-build.conf" --dbpath "$WORK/db" --cachedir "$OFFLINE" \
       -Sw --noconfirm --needed "${BASE[@]}" "${DESKTOP[@]}"

log "Building AUR packages for the offline repo"
AURBUILD="$WORK/aur"
rm -rf "$AURBUILD"; install -d -o "$SUDO_USER" "$AURBUILD"
while read -r pkg; do
    sudo -u "$SUDO_USER" git clone -q --depth 1 "https://aur.archlinux.org/$pkg.git" "$AURBUILD/$pkg"
    (cd "$AURBUILD/$pkg" && sudo -u "$SUDO_USER" makepkg -s --noconfirm --needed >/dev/null)
    cp "$AURBUILD/$pkg"/*.pkg.tar.zst "$OFFLINE/"
done < <(read_list "$REPO/packages/aur-offline.txt")

log "Indexing the offline repo"
rm -f "$OFFLINE"/*.sig "$OFFLINE"/offline.db* "$OFFLINE"/offline.files*
repo-add -q "$OFFLINE/offline.db.tar.gz" "$OFFLINE"/*.pkg.tar.zst

# ---- 3. the rice + wallpapers + logo --------------------------------------------
log "Copying the sanganak repo (working tree) into the image"
install -d "$PROFILE_DIR/airootfs/root/sanganak"
git -C "$REPO" ls-files -z --cached --others --exclude-standard \
    | (cd "$REPO" && rsync -a --from0 --files-from=- ./ "$PROFILE_DIR/airootfs/root/sanganak/")
if [[ -z "$WALLPAPERS" && -d "$(getent passwd "$SUDO_USER" | cut -d: -f6)/Work/wallpapers" ]]; then
    WALLPAPERS="$(getent passwd "$SUDO_USER" | cut -d: -f6)/Work/wallpapers"
fi
if [[ -n "$WALLPAPERS" ]]; then
    log "Bundling wallpapers from $WALLPAPERS"
    install -d "$PROFILE_DIR/airootfs/root/sanganak-wallpapers"
    find "$WALLPAPERS" -maxdepth 1 -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) \
        -exec cp {} "$PROFILE_DIR/airootfs/root/sanganak-wallpapers/" \;
fi
# mkarchiso resets airootfs modes to 644 unless profiledef lists them, which
# made every script in the bundled repo non-executable (theme-ly.sh "command
# not found" during the chroot stage). List each executable.
while IFS= read -r -d '' f; do
    printf 'file_permissions+=(["/root/sanganak/%s"]="0:0:755")\n' "${f#./}" >> "$PROFILE_DIR/profiledef.sh"
done < <(cd "$PROFILE_DIR/airootfs/root/sanganak" && find . -type f -perm -u+x -print0)

install -d "$PROFILE_DIR/airootfs/usr/share/sanganak"
python3 -I "$REPO/scripts/arch-logo.py" ansi "$PROFILE_DIR/airootfs/usr/share/sanganak/logo.ansi" "#f0522d"

# ---- 4. build -----------------------------------------------------------------------
log "Running mkarchiso"
mkarchiso -v -w "$WORK/build" -o "$OUT" "$PROFILE_DIR"
chown -R "$SUDO_USER:" "$OUT"
$KEEP_WORK || rm -rf "$WORK/build"
iso="$(ls -t "$OUT"/sanganak-*.iso | head -n1)"
(cd "$OUT" && sha256sum "$(basename "$iso")" > "$(basename "$iso").sha256")
log "Done: $iso ($(du -h "$iso" | cut -f1))"
