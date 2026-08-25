#!/usr/bin/env bash
# pre-wipe-backup — collect everything off this machine that a reinstall cannot
# recreate, and nothing that it can.
#
# Deliberately NOT backed up (all re-downloadable, ~190G of the 296G home):
#   ~/.local/share/Steam      182G — game list is captured instead, see manifest
#   ~/.config/google-chrome     9G — profile syncs from the Google account
#   ~/.config/discord         1.3G — cache
#   ~/.cache                       — yay build trees, thumbnails
#
# Usage:  bash pre-wipe-backup.sh /run/media/arjun/Ventoy
#         bash pre-wipe-backup.sh --dry-run
set -euo pipefail

DEST="${1:-}"
DRY=0
[ "$DEST" = "--dry-run" ] && { DRY=1; DEST="/tmp/prewipe-dryrun"; }
[ -n "$DEST" ] || { echo "usage: $0 <destination-dir> | --dry-run" >&2; exit 1; }

STAMP=$(date +%Y%m%d-%H%M)
OUT="$DEST/arch-prewipe-$STAMP"
mkdir -p "$OUT/manifest"

echo "==> writing to $OUT"

# ── 1. Manifests: how to rebuild, not what to restore ────────────────────────
pacman -Qqe                > "$OUT/manifest/pkgs-explicit.txt"
pacman -Qqm                > "$OUT/manifest/pkgs-aur.txt"
pacman -Qq                 > "$OUT/manifest/pkgs-all.txt"
systemctl list-unit-files --state=enabled --no-pager \
                           > "$OUT/manifest/systemd-system-enabled.txt" 2>/dev/null || true
systemctl --user list-unit-files --state=enabled --no-pager \
                           > "$OUT/manifest/systemd-user-enabled.txt"   2>/dev/null || true
lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINT,MODEL,SERIAL \
                           > "$OUT/manifest/disk-layout.txt"
efibootmgr -v 2>/dev/null  > "$OUT/manifest/efi-boot-entries.txt" || true
cat /etc/fstab             > "$OUT/manifest/fstab.txt" 2>/dev/null || true

# Steam library, so games can be re-queued without hunting through a wishlist.
if [ -d "$HOME/.local/share/Steam/steamapps" ]; then
    grep -h '"name"' "$HOME"/.local/share/Steam/steamapps/appmanifest_*.acf 2>/dev/null \
        | sed 's/.*"name"[^"]*"\([^"]*\)".*/\1/' | sort -u \
        > "$OUT/manifest/steam-games.txt" || true
fi

# ── 2. The genuinely irreplaceable payload ───────────────────────────────────
# OpenRGB config is load-bearing: OpenRGB.json carries the DISABLED Wooting
# detector. Losing it means a fresh OpenRGB would happily grab the keyboard.
copy() {
    local src="$1"
    [ -e "$HOME/$src" ] || return 0
    mkdir -p "$OUT/home/$(dirname "$src")"
    cp -a "$HOME/$src" "$OUT/home/$src" 2>/dev/null || true
    echo "    + $src"
}

echo "==> copying user data"
copy Documents
copy Pictures
copy .ssh
copy .gnupg
copy .zsh_history
copy .zshrc

# Downloads minus the installer ISOs (5.9G of omarchy-4.0.0.iso is not payload).
if [ -d "$HOME/Downloads" ]; then
    mkdir -p "$OUT/home/Downloads"
    rsync -a --exclude='*.iso' --exclude='*.img' \
        "$HOME/Downloads/" "$OUT/home/Downloads/" 2>/dev/null \
        || cp -a "$HOME/Downloads/." "$OUT/home/Downloads/" 2>/dev/null || true
    find "$OUT/home/Downloads" -name '*.iso' -delete 2>/dev/null || true
    echo "    + Downloads (ISOs excluded)"
fi

echo "==> copying configs"
copy .config/OpenRGB
copy .config/rice
copy .config/niri
copy .config/quickshell
copy .config/alacritty
copy .config/mako
copy .config/cava
copy .config/hypr
copy .config/kanshi
copy .config/btop
copy .config/fastfetch
copy .config/wooting-bg-service
copy .config/darktable
copy .local/bin
copy .spicetify

# Heroic: keep the store/config JSON, drop the multi-GB cache.
if [ -d "$HOME/.config/heroic" ]; then
    mkdir -p "$OUT/home/.config/heroic"
    for f in config.json GamesConfig store store_cache; do
        [ -e "$HOME/.config/heroic/$f" ] && \
            cp -a "$HOME/.config/heroic/$f" "$OUT/home/.config/heroic/" 2>/dev/null || true
    done
    echo "    + .config/heroic (config only)"
fi

# ── 3. Root-owned bits worth keeping a copy of ───────────────────────────────
echo "==> /etc snapshots (best effort, needs sudo)"
mkdir -p "$OUT/etc"
for f in /etc/fstab /etc/hostname /etc/locale.conf /etc/vconsole.conf \
         /etc/systemd/network/20-wired.network /etc/iwd/main.conf \
         /etc/resolv.conf /etc/ly/config.ini; do
    [ -r "$f" ] && { mkdir -p "$OUT/etc$(dirname "${f#/etc}")"; cp -a "$f" "$OUT/etc/${f#/etc/}" 2>/dev/null; } || true
done
sudo -n cp -a /var/lib/iwd "$OUT/etc/iwd-psk" 2>/dev/null && echo "    + saved wifi PSKs" \
    || echo "    ! wifi PSKs skipped (need: sudo cp -a /var/lib/iwd $OUT/etc/iwd-psk)"

# ── 4. Report ────────────────────────────────────────────────────────────────
echo
du -sh "$OUT" 2>/dev/null
echo
echo "Backed up to: $OUT"
echo "NOT included (by design): Steam library, Chrome profile, Discord, caches."
[ "$DRY" = 1 ] && echo "(dry run — inspect then: rm -rf $OUT)"
