# Wipe readiness — desktop (B650 EAGLE AX)

Written 2026-08-25, before reinstalling onto Omarchy.

## The one thing that can go wrong

This machine has **two identical drives**. Same model, same size, same
everything an installer puts on screen:

| Serial | Model | Role | Contents |
|---|---|---|---|
| `242849D4A723` | Crucial CT1000P3PSSD8 1TB | **WINDOWS — do not touch** | 100M ESP, 16M MSR, 930.6G NTFS, 842M recovery |
| `24504CC94939` | Crucial CT1000P3PSSD8 1TB | **LINUX — wipe target** | 1G ESP, 930.5G ext4 |

They currently enumerate as `nvme0n1` (Windows) and `nvme1n1` (Linux), but
**that is not stable**. NVMe names are assigned in PCIe enumeration order and can
swap between boots and kernels. The installer's live kernel is not this kernel.

> **Never select an install disk by `nvme0n1`/`nvme1n1`. Only by serial.**

The drives sit on separate CPU root ports — Windows on `00:01.2` (bus 04),
Linux on `00:03.1` (bus 12) — so they are in different physical M.2 sockets.

## Protection: make the Windows drive invisible

`scripts/protect-windows-drive.sh` locates the Windows drive **by serial**,
confirms it really carries NTFS, marks it read-only, then unbinds its PCIe
function from the `nvme` driver. The device node disappears. An installer cannot
partition, format or `dd` a device that has no `/dev` node — this is the software
equivalent of pulling the stick, and a plain reboot undoes it.

Run it in the live installer, as root, **before** the partitioning step:

```bash
bash protect-windows-drive.sh            # arm
bash protect-windows-drive.sh --status   # report only, changes nothing
```

Arming prints a confirmation that exactly one drive remains visible. If it
reports the Windows drive is still visible, **stop** and use the BIOS route below
instead.

Copy the script to the Ventoy stick so it is reachable from the installer.

### Belt-and-braces: BIOS

Optional, and stronger still if your board exposes it. In BIOS look under
`Settings → IO Ports` for per-slot M.2 configuration and disable the socket
holding the Windows drive. Re-enable it after the install. I can't confirm from
here whether F4 on this board exposes that toggle — check, and if it isn't there,
the script is sufficient on its own.

## Data

`scripts/pre-wipe-backup.sh <dest>` collects the irreplaceable set — **2.3G**:

Documents, Pictures, Downloads (ISOs excluded), `.ssh`, `.gnupg`, `.zsh_history`,
`.zshrc`, `.local/bin`, `.spicetify`, and configs for OpenRGB, rice, niri,
quickshell, alacritty, mako, cava, hypr, kanshi, btop, fastfetch, darktable,
wooting-bg-service, Heroic (config only). Plus manifests: package lists, enabled
systemd units, disk layout, EFI entries, fstab, and the Steam game list.

Deliberately excluded, ~190G, all re-downloadable: Steam library (182G), Chrome
profile (9.3G, syncs from the Google account), Discord (1.3G), caches.

**`~/.config/OpenRGB/OpenRGB.json` is load-bearing** — it carries the *disabled*
Wooting detector. A fresh OpenRGB without it will happily grab the keyboard.

Wifi PSKs live in `/var/lib/iwd` and need root:

```bash
sudo cp -a /var/lib/iwd "$DEST/etc/iwd-psk"
```

### Already safe

- `arch-setup` repo — clean, pushed to `origin/main` at `3a75f76`.
- No SSH private keys exist (only `known_hosts`); no GPG secret keys.
- GitHub auth is a `gh` OAuth token — re-create with `gh auth login`, don't copy it.
- Only dirty git trees are `~/.cache/yay` build dirs. Disposable.

## Firmware

- Secure Boot is **enabled (user)** with sbctl keys enrolled. Omarchy's preflight
  requires it **off**.
- **Check BitLocker from Windows first: `manage-bde -status`.** `lsblk` reports
  the Windows partition as plain `ntfs` rather than `BitLocker`, which indicates
  it is *not* encrypted — but confirm from Windows, and if it is on, save the
  recovery key from account.microsoft.com/devices/recoverykey **on paper** before
  touching any firmware setting. Toggling Secure Boot rewrites PCR 7.
- Current root is **ext4**. Omarchy's guard wants **btrfs** (for
  `omarchy-snapshot`). The new install must be btrfs.

## Installer media

`~/Downloads/omarchy-4.0.0.iso` — 6273040384 bytes,
sha256 `9224fab3720560f771969a99a499e5f7e0f8e2d6a0681d872d52f05fb5003da4`.

Upstream is now **4.0.1**; consider re-downloading. Omarchy publishes no
checksum, so the hash above is only useful for confirming the file hasn't
changed on disk since today.
