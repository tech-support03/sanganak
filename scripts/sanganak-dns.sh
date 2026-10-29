#!/usr/bin/env bash
# sanganak-dns — pick the DNS servers. The rice has no systemd-resolved and no
# NetworkManager: DNS is the static /etc/resolv.conf (CLAUDE.md §2), so a
# provider choice rewrites that file. The network panel's DNS row runs this.
#
#   sanganak-dns                  print the current provider:
#                                 DHCP | Cloudflare | Google | Custom
#   sanganak-dns Cloudflare       (root) 1.1.1.1, 1.0.0.1, 2606:4700:4700::1111
#   sanganak-dns Google           (root) 8.8.8.8, 8.8.4.4, 2001:4860:4860::8888
#   sanganak-dns DHCP             (root) the servers the network hands out
#   sanganak-dns Custom IP...     (root) up to three addresses of your own
#   sanganak-dns --custom         ask for addresses, then `sudo … Custom` (the
#                                 panel opens this in a floating terminal)
#
# DHCP: on a wired link, the DNS option of systemd-networkd's DHCPv4 lease
# (`networkctl status --json`; networkd keeps it even with UseDNS=no). On Wi-Fi,
# iwd discards the offered servers (NameResolvingService=none), so the gateway
# — which on nearly every router answers DNS — stands in. The panel re-runs
# `DHCP` when the uplink changes, so it follows you between networks.
#
# 07-services.sh lets the wheel group run the Cloudflare / Google / DHCP forms
# without a password; Custom asks for one (any server could be typed in).
set -Eeuo pipefail

CONF=/etc/resolv.conf
MARK="# sanganak-dns:"

current() {
    local mark first
    mark="$(sed -n "s/^$MARK[[:space:]]*//p" "$CONF" 2>/dev/null | head -1)"
    [[ -n "$mark" ]] && { echo "$mark"; return; }
    # Unmarked (the installer's seed is 1.1.1.1 + 8.8.8.8): go by the first server.
    first="$(awk '/^nameserver/ {print $2; exit}' "$CONF" 2>/dev/null)"
    case "$first" in
        1.1.1.1|1.0.0.1|2606:4700:4700::1111|2606:4700:4700::1001) echo Cloudflare ;;
        8.8.8.8|8.8.4.4|2001:4860:4860::8888|2001:4860:4860::8844) echo Google ;;
        "") echo DHCP ;;
        *)  echo Custom ;;
    esac
}

valid_ip() {
    [[ "$1" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] && {
        local IFS=. o; for o in $1; do (( o <= 255 )) || return 1; done; return 0; }
    [[ "$1" =~ ^[0-9a-fA-F:]+$ && "$1" == *:* ]]
}

# The network's own servers, best effort (see the header).
dhcp_servers() {
    local dev gw hex
    # The default route with the lowest metric is the uplink in use.
    read -r dev gw < <(ip -o -4 route show default 2>/dev/null | awk '
        { m = 0; d = ""; g = ""
          for (i = 1; i < NF; i++) { if ($i == "dev") d = $(i+1); if ($i == "via") g = $(i+1); if ($i == "metric") m = $(i+1) }
          if (best == "" || m + 0 < best) { best = m + 0; bd = d; bg = g } }
        END { if (bd != "") print bd, bg }')
    [[ -n "${dev:-}" ]] || return 1
    hex="$(networkctl status "$dev" --json=short 2>/dev/null \
        | jq -r '.DHCPv4Client.Lease.Message.options[]? | select(.tag == 6) | .data' 2>/dev/null | head -1)"
    if [[ "$hex" =~ ^([0-9a-fA-F]{8})+$ ]]; then
        local i; for (( i = 0; i < ${#hex} && i < 24; i += 8 )); do
            printf '%d.%d.%d.%d\n' "0x${hex:i:2}" "0x${hex:i+2:2}" "0x${hex:i+4:2}" "0x${hex:i+6:2}"
        done
    elif [[ -n "${gw:-}" ]]; then
        echo "$gw"
    else
        return 1
    fi
}

write_conf() {   # provider, then servers
    local provider="$1"; shift
    [[ $EUID -eq 0 ]] || { echo "sanganak-dns: run as root (sudo sanganak-dns $provider)" >&2; exit 1; }
    [[ $# -ge 1 ]] || { echo "sanganak-dns: no servers for $provider" >&2; exit 1; }
    local tmp; tmp="$(mktemp /etc/.resolv.conf.XXXXXX)"
    {
        echo "# Written by sanganak-dns — change it from the network panel's DNS row."
        echo "$MARK $provider"
        local s; for s in "${@:1:3}"; do echo "nameserver $s"; done
    } > "$tmp"
    chmod 644 "$tmp"
    mv -f "$tmp" "$CONF"        # replaces a symlink too; nothing else manages this file
    echo "DNS → $provider (${*:1:3})"
}

ask_custom() {
    local line
    if command -v gum >/dev/null; then
        line="$(gum input --placeholder "e.g. 9.9.9.9 149.112.112.112" --header "DNS servers (space-separated, up to 3)")" || exit 1
    else
        read -rp "DNS servers (space-separated, up to 3): " line
    fi
    # shellcheck disable=SC2086
    sudo "$(readlink -f "$0")" Custom $line && sleep 1
}

case "${1:-}" in
    "")          current ;;
    Cloudflare)  write_conf Cloudflare 1.1.1.1 1.0.0.1 2606:4700:4700::1111 ;;
    Google)      write_conf Google 8.8.8.8 8.8.4.4 2001:4860:4860::8888 ;;
    DHCP)        mapfile -t servers < <(dhcp_servers) || true
                 [[ ${#servers[@]} -gt 0 ]] || { echo "sanganak-dns: no network to take DNS from" >&2; exit 1; }
                 write_conf DHCP "${servers[@]}" ;;
    Custom)      shift
                 [[ $# -ge 1 && $# -le 3 ]] || { echo "sanganak-dns: Custom takes 1-3 addresses" >&2; exit 1; }
                 for s in "$@"; do valid_ip "$s" || { echo "sanganak-dns: not an IP address: $s" >&2; exit 1; }; done
                 write_conf Custom "$@" ;;
    --custom)    ask_custom ;;
    *)           echo "usage: sanganak-dns [Cloudflare|Google|DHCP|Custom IP...|--custom]" >&2; exit 2 ;;
esac
