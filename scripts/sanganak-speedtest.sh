#!/usr/bin/env bash
# sanganak-speedtest — download or upload speed with curl alone. The network
# panel runs `down`, then `up`.
#
#   sanganak-speedtest down|up
#
# Prints, a line at a time: "src <where>", the live rate in Mbps every half
# second (read off the uplink's byte counter), then "avg <Mbps>". Four streams
# run in parallel. The average runs from the end of a 1 s warm-up to the moment
# the first stream completes — every stream is still moving data in that
# window, so one stalled connection can't drag the result down — and then the
# rest are stopped.
#
# Where: Cloudflare's speed test (speed.cloudflare.com, its nearest edge).
# Cloudflare rate-limits it per IP: after a burst of requests it answers 429 for
# up to an hour. So a run sends few — one probe, then at most two transfers per
# stream (50 MB down, 25 MB up). A download that meets a 429 moves to whichever
# of a few public test-file mirrors answers a short probe fastest; an upload has
# no such fallback and says when Cloudflare will take it again.
set -uo pipefail

dir="${1:-}"
[[ "$dir" == down || "$dir" == up ]] || { echo "usage: sanganak-speedtest down|up" >&2; exit 2; }
iface="$(ip -o route get 1.1.1.1 2>/dev/null | sed -n 's/.* dev \([^ ]*\).*/\1/p')"
[[ -n "$iface" ]] || { echo "offline" >&2; exit 1; }
counter="/sys/class/net/$iface/statistics/$([[ $dir == down ]] && echo rx_bytes || echo tx_bytes)"

STREAMS=4 PER_STREAM=2 MAX_S=10 WARMUP_MS=1000
CF=https://speed.cloudflare.com
# Download fallbacks: plain test files. (Hetzner's allow only two connections
# per IP, so they aren't here.)
MIRRORS=(
    "Vultr Silicon Valley|https://sjo-ca-us-ping.vultr.com/vultr.com.100MB.bin"
    "Vultr Los Angeles|https://lax-ca-us-ping.vultr.com/vultr.com.100MB.bin"
    "Vultr New Jersey|https://nj-us-ping.vultr.com/vultr.com.100MB.bin"
    "OVH France|https://proof.ovh.net/files/100Mb.dat"
)

tmp="$(mktemp -d)"
pids=()
cleanup() { local p; for p in "${pids[@]}"; do pkill -P "$p" 2>/dev/null; kill "$p" 2>/dev/null; done; rm -rf "$tmp"; }
trap cleanup EXIT

# Ask Cloudflare without transferring anything → "<http code> <Retry-After or ->".
# The limit is on size (small requests still pass while big ones get 429), so
# the download probe is a HEAD of the real 50 MB URL. Uploads can only be
# probed with a token POST; a 429 on a real one is caught by the streams.
cf_status() {
    local hdr
    if [[ $dir == down ]]; then hdr="$(curl -s -I -o /dev/null -D - --max-time 5 "$CF/__down?bytes=50000000")"
    else hdr="$(curl -s -o /dev/null -D - --max-time 5 --data-binary x "$CF/__up")"; fi
    awk 'NR == 1 { code = $2 } tolower($1) == "retry-after:" { ra = $2 + 0 }
         END { print (code ? code : "000"), (ra ? ra : "-") }' <<<"${hdr//$'\r'/}"
}

# The mirror that moves a 4 MB range fastest, as "name|url" (probed in parallel).
fastest_mirror() {
    local m
    for m in "${MIRRORS[@]}"; do
        curl -s -o /dev/null -r 0-3999999 --max-time 3 -w "%{http_code} %{speed_download} $m\n" "${m#*|}" &
    done | awk '$1 == 200 || $1 == 206 { print $2, $0 }' | sort -rn | head -1 | cut -d' ' -f4-
}

read -r code retry < <(cf_status)
if [[ "$code" == 2* ]]; then
    src="Cloudflare"
    [[ $dir == down ]] && URL="$CF/__down?bytes=50000000" || URL="$CF/__up"
elif [[ $dir == down ]]; then
    m="$(fastest_mirror)"
    [[ -n "$m" ]] || { echo "no speed test server answered (Cloudflare: HTTP $code)" >&2; exit 1; }
    src="${m%%|*}"; URL="${m#*|}"
    [[ "$code" == 429 ]] && src="$src (Cloudflare is rate-limiting this connection)"
elif [[ "$code" == 429 ]]; then
    [[ "$retry" != - ]] && wait_msg=" — try again in about $(( (retry + 59) / 60 )) min" || wait_msg=""
    echo "Cloudflare is rate-limiting uploads from this connection$wait_msg" >&2
    exit 1
else
    echo "Cloudflare's speed test didn't answer (HTTP $code)" >&2
    exit 1
fi

# One stream: up to PER_STREAM transfers; leaves done.N = "ok", or "fail <code>".
stream() {
    local n end=$((SECONDS + MAX_S)) left c result="fail 000"
    for (( n = 0; n < PER_STREAM; n++ )); do
        (( (left = end - SECONDS) > 0 )) || break
        if [[ $dir == down ]]; then
            c=$(curl -s -o /dev/null -w '%{http_code}' --max-time "$left" "$URL")
        else
            c=$(head -c 25000000 /dev/zero | curl -s -o /dev/null -w '%{http_code}' --max-time "$left" --data-binary @- "$URL")
        fi
        [[ "$c" == 2* ]] || { [[ $result == ok ]] || result="fail $c"; break; }   # refused: stop knocking
        result=ok
    done
    echo "$result" > "$tmp/done.$1"
}

echo "src $src"
for (( i = 0; i < STREAMS; i++ )); do stream "$i" & pids+=($!); done

now_ms() { echo $(( $(date +%s%N) / 1000000 )); }
finished() { ls "$tmp" | grep -c '^done\.'; }
t0=$(now_ms); prev=$(<"$counter"); tprev=$t0; base=$prev; tbase=$t0; warm=0
while :; do
    sleep 0.5
    cur=$(<"$counter"); t=$(now_ms)
    (( t > tprev )) && echo $(( (cur - prev) * 8 / (t - tprev) / 1000 ))   # bytes/ms → Mbps
    prev=$cur; tprev=$t
    if (( !warm && t - t0 >= WARMUP_MS )); then base=$cur; tbase=$t; warm=1; fi
    (( t - t0 >= MAX_S * 1000 )) && break
    if (( $(finished) == STREAMS )); then
        if ! grep -qsx ok "$tmp"/done.*; then
            grep -qs 'fail 429' "$tmp"/done.* \
                && echo "${src%% (*} is rate-limiting this connection — try again in a while" >&2 \
                || echo "every transfer to ${src%% (*} failed" >&2
            exit 1
        fi
        break
    fi
    # The first stream to complete ends the window (once past the warm-up).
    (( warm )) && grep -qsx ok "$tmp"/done.* && break
done
(( tprev > tbase )) && echo "avg $(( (prev - base) * 8 / (tprev - tbase) / 1000 ))"
