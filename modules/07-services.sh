#!/usr/bin/env bash
# 07-services.sh — enable system + user services. Idempotent.
set -Eeuo pipefail

# In the ISO's chroot (SANGANAK_CHROOT=1) nothing is running: the timezone
# was set by 04-chroot-config, and services are enabled without --now.
NOW="--now"
if [[ -n "${SANGANAK_CHROOT:-}" ]]; then
    NOW=""
    sudo systemctl enable systemd-timesyncd.service
else
    log "Setting timezone"
    sudo timedatectl set-timezone "${TIMEZONE:-America/Los_Angeles}"
    sudo timedatectl set-ntp true
fi

# ---- networking: iwd (wifi) + systemd-networkd (wired) ---------------------
# No NetworkManager — it fought iwd on this hardware. iwd runs standalone and
# does its own DHCP/association for wifi; systemd-networkd manages the wired
# NIC only (a lower route metric makes a plugged cable auto-win over wifi).
# DNS is deliberately left to a static /etc/resolv.conf (the live box layers
# Cloudflare WARP on top), so systemd-resolved is NOT enabled — turning it on
# would seize DNS and re-break the school content filter path.
log "Writing iwd config"
sudo install -Dm644 /dev/stdin /etc/iwd/main.conf <<'EOF'
[General]
# iwd configures the wifi link itself (address, routes, its own DHCP).
EnableNetworkConfiguration=true

[Network]
# Don't let iwd touch DNS — a static /etc/resolv.conf (+ WARP) owns it.
NameResolvingService=none
EOF

log "Writing systemd-networkd wired profile"
sudo install -Dm644 /dev/stdin /etc/systemd/network/20-wired.network <<'EOF'
# Wired NIC, managed by systemd-networkd (iwd still owns wifi). DHCP supplies
# address + routes only; DNS is left to the static /etc/resolv.conf (+ WARP)
# via UseDNS=no, so networkd never disturbs the (school-filtered) DNS path. A
# low RouteMetric makes a plugged-in cable win over wifi automatically;
# RequiredForOnline=no keeps an unplugged cable from stalling boot.
[Match]
Name=en*

[Network]
DHCP=yes

[Link]
RequiredForOnline=no

[DHCPv4]
RouteMetric=100
UseDNS=no

[IPv6AcceptRA]
RouteMetric=100
UseDNS=no
EOF

log "Writing polkit rule for the network flyout's wired override toggle"
sudo install -Dm644 /dev/stdin /etc/polkit-1/rules.d/50-networkd-links.rules <<'EOF'
// Let the active local session bring networkd-managed links up/down without a
// password — used by the Quickshell network flyout's manual Ethernet override.
// Scoped to link management only; DNS / route-policy actions still need admin.
polkit.addRule(function(action, subject) {
    if (action.id == "org.freedesktop.network1.manage-links" &&
        subject.local && subject.active) {
        return polkit.Result.YES;
    }
});
EOF

# Seed a static resolver if one isn't already in place (the live box points
# this at 1.1.1.1/8.8.8.8 and runs WARP over the top). Never clobber an
# existing resolv.conf — it may be a deliberate WARP/resolved setup.
if [[ ! -s /etc/resolv.conf ]]; then
    log "Seeding static /etc/resolv.conf"
    printf 'nameserver 1.1.1.1\nnameserver 8.8.8.8\n' | sudo tee /etc/resolv.conf >/dev/null
fi

log "Enabling system services"
sudo systemctl enable $NOW iwd.service
sudo systemctl enable $NOW systemd-networkd.service
sudo systemctl enable $NOW bluetooth.service
sudo systemctl enable $NOW seatd.service
sudo usermod -aG seat,video,input,audio,wheel "$USER" || true

log "Enabling ly login manager"
sudo systemctl enable ly@tty1.service

# Theme the greeter from the rice palette (falls back to deccan if rice-theme
# hasn't run yet). Idempotent; only edits colour/appearance keys in place.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
sudo "$REPO_ROOT/scripts/theme-ly.sh" || log "ly theming skipped (run later: sudo scripts/theme-ly.sh)"

# After that, rice-theme keeps the greeter in step with every theme switch (the
# pywal theme changes it with each wallpaper) by running theme-ly without a
# password: exactly /usr/local/bin/theme-ly (root-owned, installed by
# 08-link-dotfiles.sh) and only with NO arguments — it then reads the invoking
# user's ~/.config/rice/colors and accepts nothing but #rrggbb values.
sudo install -Dm440 /dev/stdin /etc/sudoers.d/30-theme-ly <<'CONF'
# rice-theme re-themes the ly login screen on every theme switch.
%wheel ALL=(root) NOPASSWD: /usr/local/bin/theme-ly ""
CONF
sudo visudo -cf /etc/sudoers.d/30-theme-ly >/dev/null || { sudo rm -f /etc/sudoers.d/30-theme-ly; log "theme-ly sudoers rule rejected — removed"; }

# The network panel's DNS row rewrites /etc/resolv.conf through sanganak-dns.
# The three fixed providers run without a password; Custom (any server could be
# typed in) is deliberately left out, so sudo asks for it in a terminal.
sudo install -Dm440 /dev/stdin /etc/sudoers.d/40-sanganak-dns <<'CONF'
# The network panel switches DNS between the fixed providers.
%wheel ALL=(root) NOPASSWD: /usr/local/bin/sanganak-dns Cloudflare, /usr/local/bin/sanganak-dns Google, /usr/local/bin/sanganak-dns DHCP
CONF
sudo visudo -cf /etc/sudoers.d/40-sanganak-dns >/dev/null || { sudo rm -f /etc/sudoers.d/40-sanganak-dns; log "sanganak-dns sudoers rule rejected — removed"; }

# Hypervisor guest agent for the hypervisor we're running under (none on
# bare metal); all of them are installed from desktop.txt.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
for unit in $(vm_guest_units); do
    sudo systemctl enable "$unit" 2>/dev/null || true
done

log "Enabling user services"
# pipewire / wireplumber are socket- or preset-activated per user; enabling
# globally covers the chroot, where there is no user manager to talk to.
for unit in pipewire.socket pipewire-pulse.socket wireplumber.service; do
    sudo systemctl --global enable "$unit" 2>/dev/null || true
done

ok "services enabled"
