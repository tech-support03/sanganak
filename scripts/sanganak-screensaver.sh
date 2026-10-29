#!/usr/bin/env bash
# sanganak-screensaver — Omarchy-style screensaver: the संगणक wordmark (block
# art in the ANSI Shadow style, rendered from Noto Sans Devanagari Bold) run
# through a random tte (terminaltexteffects) effect in a fullscreen terminal on
# every output, settling in the theme colours. Any key, pointer movement or
# focus change ends it. It never locks and never blanks the screen.
#
#   sanganak-screensaver          start it on every output. Quickshell runs this
#                                 after 2.5 min idle (overlays/Screensaver.qml);
#                                 the sanganak menu runs it on demand
#   sanganak-screensaver --stop   end it (Quickshell runs this on activity)
#   sanganak-screensaver --run    the loop inside each terminal (internal)
#
# niri's window rule for app-id sanganak.screensaver opens each terminal
# fullscreen with no focus ring, and keeps it opaque while unfocused.
set -uo pipefail

CLASS="sanganak.screensaver"
TXT="${XDG_RUNTIME_DIR:-/tmp}/sanganak-screensaver.txt"

stop_all() { pkill -f -- "--class $CLASS" 2>/dev/null || true; }

# Count this screensaver's windows niri has mapped.
mapped() { niri msg --json windows 2>/dev/null | jq --arg c "$CLASS" '[.[] | select(.app_id == $c)] | length' 2>/dev/null || echo 0; }

launch() {
    command -v tte >/dev/null 2>&1 || {
        notify-send -u low "Screensaver" "tte is not installed (yay -S python-terminaltexteffects)" 2>/dev/null
        exit 1
    }
    pgrep -f -- "--class $CLASS" >/dev/null && exit 0     # already running
    pgrep -x hyprlock >/dev/null && exit 0                 # locked: nothing to show
    # A gamepad isn't Wayland input, so a game looks idle: never cover one.
    [[ "$(niri msg --json focused-window 2>/dev/null | jq -r '.app_id // empty')" =~ ^(gamescope|steam_app_) ]] && exit 0
    local focused outs o n=0
    focused="$(niri msg --json focused-output 2>/dev/null | jq -r '.name // empty')"
    mapfile -t outs < <(niri msg --json outputs | jq -r 'to_entries[] | select(.value.current_mode != null) | .key')
    for o in "${outs[@]}"; do
        # niri opens a window on the output focused when it maps, so focus each
        # output in turn and wait for its terminal before moving on.
        niri msg action focus-monitor "$o"
        setsid -f alacritty --class "$CLASS" --title "screensaver" \
            -o 'colors.primary.background="#000000"' -o 'window.opacity=1.0' -o 'font.size=18' \
            -e "$0" --run >/dev/null 2>&1
        n=$((n + 1))
        for _ in $(seq 1 30); do (( $(mapped) >= n )) && break; sleep 0.1; done
    done
    # Back to where you were: that output's active window is now its screensaver.
    [[ -n "$focused" ]] && niri msg action focus-monitor "$focused"
}

run() {
    local pid="" effect start stops rate effects
    trap '[[ -n "$pid" ]] && kill "$pid" 2>/dev/null; exit 0' HUP INT TERM
    # संगणक — block and box-drawing characters only, so tte animates it like
    # any text and no Devanagari shaping is needed in the terminal.
    cat > "$TXT" <<'WORDMARK'
             ███╗
             ███║
             ███║
             ╚══╝
██████████████████████████████████████████████████████████████████████████╗
██████████████████████████████████████████████████████████████████████████║
╚════████║═══███║════███║═══████║══████║══███║══███║══════════████║═══════╝
     ████║   ███║    ███║   ████║  ████║  ███║  ███║    ██████████║
 ████████║   ███║   ████║   ████║  ████║  ███║  ███║  ██████████████████╗
 ███████████████║  █████║   ████║  ████║  ███║  ███║  ████║═══███████████╗
 █████║█████████║  █████║   ████║  ██████████║  ███║  ████║   ████║══████║
 ╚████║╚═════███║  ╚═███║   ████║  ╚████████║╝  ███║  ╚███████████║  ████║
  ╚█████╗    ███║    ╚══╝   ████║   ╚══███║═╝   ███║   ╚██████████║ ████║╝
   ╚═████╗   ███║           ████║      ╚══╝     ███║    ╚═════████║ ╚███║
     ╚██║╝   ███║           ███║╝               ███║          ╚███║  ╚══╝
      ╚═╝    ╚══╝           ╚══╝                ╚══╝           ╚══╝
WORDMARK
    # Settle on the focus ring's gradient: accent → c2 of the live palette.
    mapfile -t stops < <(grep -oE '#[0-9a-fA-F]{6}' "$HOME/.config/rice/colors" 2>/dev/null | head -2 | tr -d '#')
    [[ ${#stops[@]} -eq 2 ]] || stops=(f0522d dfe5eb)
    # Python tte is CPU-bound per frame; the light profile halves the rate.
    rate=120; [[ "$(cat "$HOME/.config/rice/profile" 2>/dev/null)" == light ]] && rate=60
    # Every effect tte offers except synthgrid, which takes no gradient stops.
    mapfile -t effects < <(tte -h | tr -d '\n ' | grep -oE '\{beams[^}]*\}' | head -1 | tr -d '{}' | tr ',' '\n' | grep -vx synthgrid)
    [[ ${#effects[@]} -gt 0 ]] || effects=(beams)

    printf '\e[?25l\e[?1003h'     # hide the cursor; report pointer motion as input
    start=$SECONDS
    sleep 1                       # the click / key that launched us is not "activity"
    while read -rsn1 -t 0.05; do :; done

    while true; do
        effect="${effects[RANDOM % ${#effects[@]}]}"
        tte -i "$TXT" --frame-rate "$rate" --canvas-width 0 --canvas-height $(( $(tput lines) - 2 )) \
            --anchor-canvas c --anchor-text c --no-eol --no-restore-cursor \
            "$effect" --final-gradient-stops "${stops[@]}" --final-gradient-direction diagonal &
        pid=$!
        while kill -0 "$pid" 2>/dev/null; do
            read -rsn1 -t 1 && { stop_all; exit 0; }
            # Focus left the screensaver (a click elsewhere, a keybind). Give the
            # launcher a few seconds to map every output's terminal first.
            if (( SECONDS - start > 4 )) &&
               [[ "$(niri msg --json focused-window 2>/dev/null | jq -r '.app_id // empty')" != "$CLASS" ]]; then
                stop_all; exit 0
            fi
        done
        pid=""
    done
}

case "${1:-}" in
    --run)  run ;;
    --stop) stop_all ;;
    "")     launch ;;
    *)      echo "usage: sanganak-screensaver [--stop]" >&2; exit 2 ;;
esac
