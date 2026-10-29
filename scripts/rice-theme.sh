#!/usr/bin/env bash
# rice-theme — apply a 4-colour palette across the WHOLE rice, live.
#
#   rice-theme status            print the active theme name
#   rice-theme list              list saved themes (● = active)
#   rice-theme set <name>        apply a saved theme
#   rice-theme apply-colors c1 c2 c3 c4   apply 4 colours LIVE, without saving
#   rice-theme next              cycle to the next saved theme (+ notification)
#   rice-theme create <name> c1 c2 c3 c4 [base]   write a new theme (base optional)
#   rice-theme save <name>       snapshot the CURRENT live palette as <name>
#   rice-theme apply             re-apply the active theme (used at boot)
#   rice-theme wal [image]       derive the palette from the wallpaper (pywal) and
#                                keep following it ("set wal" is the same)
#   rice-theme wal-sync [image]  wallpaper scripts call this: re-derive only while
#                                the wallpaper theme is active (quiet, no reminder)
#
# A "theme" is four colours (c1=accent/hero, c2=blue, c3=cyan, c4=teal) plus an
# optional base= (the near-black every bar/panel/notification/terminal sits on;
# themes without it keep the legacy neutral #0f1016). Every
# other shade — bright/dim/muted accents, the album-art tint, btop's gradients —
# is DERIVED here, so you only ever choose four. Design mirrors `rice-profile`:
#   • Quickshell reads ~/.config/rice/colors LIVE (Theme.qml FileView) → no restart.
#   • niri's focus ring is GENERATED into ~/.config/niri/colors.kdl, which the
#     niri config includes; niri live-reloads included files.
#   • btop / hyprlock / fastfetch / zsh can't watch a file, so they're GENERATED
#     from templates into ~/.config and pick up the change on next launch.
#   • the ly login screen is root-owned: theme-ly runs through a NOPASSWD sudoers
#     rule (07-services.sh) after every switch. Limine stays manual (re-signing).
#   • Zen's workspace colours (c1, c2) via zen-theme — applied while Zen is
#     closed, otherwise queued until it exits.
#
# The "wal" theme is pywal (python-pywal16): `wal` reads the current wallpaper
# (~/.cache/wallpaper-current, written by wallpaper-init / wallpaper-next) and
# its 16 colours are mapped onto c1..c4 + base, then applied like any palette.
set -Eeuo pipefail

RICE_DIR="$HOME/.config/rice"
THEMES_DIR="$RICE_DIR/themes"
TPL_DIR="$RICE_DIR/templates"
ACTIVE_FILE="$RICE_DIR/theme"
COLORS_FILE="$RICE_DIR/colors"     # 4 hex lines — Quickshell Theme.qml reads this live
COLORS_SH="$RICE_DIR/colors.sh"    # shell vars — ~/.zshrc sources this for the prompt

BTOP_THEME="$HOME/.config/btop/themes/sanganak.theme"
HYPRLOCK_CONF="$HOME/.config/hypr/hyprlock.conf"
FASTFETCH_CFG="$HOME/.config/fastfetch/config.jsonc"
MAKO_CFG="$HOME/.config/mako/config"
ALACRITTY_COLORS="$RICE_DIR/alacritty-colors.toml"   # imported by alacritty.toml
NIRI_COLORS="$HOME/.config/niri/colors.kdl"          # included by the niri config
WAL_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/wal"
WALLPAPER_CURRENT="${XDG_CACHE_HOME:-$HOME/.cache}/wallpaper-current"
WAL_PALETTE="$RICE_DIR/wal.palette"   # last wallpaper palette — the picker's swatch
LEGACY_BASE="#0f1016"
DEFAULT_THEME="deccan"

c_info() { printf '\033[34m::\033[0m %s\n' "$*"; }
c_err()  { printf '\033[31mrice-theme:\033[0m %s\n' "$*" >&2; }
die()    { c_err "$*"; exit 1; }

# Parse c1..c4 (and name) out of a theme file into globals C1..C4 / TNAME.
load_theme_file() {
    local f="$1" k v
    [[ -r "$f" ]] || die "no such theme: $f"
    TNAME="$(basename "$f" .theme)"; C1=""; C2=""; C3=""; C4=""; BASE=""
    while IFS='=' read -r k v; do
        k="${k// /}"; v="${v// /}"
        case "$k" in
            name) TNAME="$v" ;;
            c1) C1="$v" ;; c2) C2="$v" ;; c3) C3="$v" ;; c4) C4="$v" ;;
            base) BASE="$v" ;;
        esac
    done < <(grep -vE '^\s*#|^\s*$' "$f")
    [[ "$C1$C2$C3$C4" =~ ^(#[0-9a-fA-F]{6}){4}$ ]] || \
        die "theme '$TNAME' must define 4 hex colours c1..c4 (got: $C1 $C2 $C3 $C4)"
    [[ -z "$BASE" || "$BASE" =~ ^#[0-9a-fA-F]{6}$ ]] || die "theme '$TNAME': base must be #rrggbb (got: $BASE)"
}

# Replace a possible symlink target with a real file (never write through the
# repo symlink) — same trick 08-link-dotfiles.sh uses for niri's config.kdl.
write_real() { local dst="$1"; mkdir -p "$(dirname "$dst")"; [[ -L "$dst" ]] && rm -f "$dst"; cat > "$dst"; }

active_name() { [[ -r "$ACTIVE_FILE" ]] && tr -d ' \n' < "$ACTIVE_FILE" || echo ""; }

# Some rice surfaces live on root-owned files that only apply at boot / greeter
# (the Secure-Boot-signed ESP boot menu, and ly's /etc login config). ly follows
# every switch through its sudoers rule (apply_palette); Limine needs a re-sign,
# so it never changes on its own. Instead, after a user-driven switch we compare the palette we just
# applied (C1..C4) against the one each surface was last built from (stamped as a
# '# rice-synced-colors:' comment) and fire ONE reminder listing whatever drifted.
# Only surfaces that are themed at all (file present + stamped) are checked; this
# never touches those files.
surfaces_sync_reminder() {
    local cur stamp name file cmd drift=()
    cur="$(echo "$C1 $C2 $C3 $C4${BASE:+ $BASE}" | tr 'A-Z' 'a-z')"
    while IFS='|' read -r name file cmd; do
        [[ -r "$file" ]] || continue
        stamp="$(sed -n 's/^# rice-synced-colors:[[:space:]]*//p' "$file" | tr 'A-Z' 'a-z')"
        stamp="$(echo $stamp)"                       # collapse whitespace + trim
        [[ -n "$stamp" && "$stamp" != "$cur" ]] && drift+=("• $name → $cmd")
    done <<'SURFACES'
boot menu|/etc/limine-theme.conf|sudo theme-limine
login screen|/etc/ly/config.ini|sudo theme-ly
SURFACES
    [[ ${#drift[@]} -gt 0 ]] || return 0
    command -v notify-send >/dev/null 2>&1 && \
        notify-send -t 6000 -u low "Theme: resync boot/login surfaces" \
            "$(printf '%s\n' "${drift[@]}")" || true
}

themes_list() { find "$THEMES_DIR" -maxdepth 1 -name '*.theme' -printf '%f\n' 2>/dev/null | sed 's/\.theme$//' | sort; }

# ---- the core: apply C1..C4 everywhere --------------------------------------
apply_palette() {
    mkdir -p "$RICE_DIR"
    # 1) Quickshell — live via Theme.qml's FileView. c1..c4, then base if set.
    printf '%s\n%s\n%s\n%s\n' "$C1" "$C2" "$C3" "$C4" > "$COLORS_FILE"
    [[ -n "${BASE:-}" ]] && printf '%s\n' "$BASE" >> "$COLORS_FILE"

    # 2) Everything that can't watch a file: derive shades + render in Python.
    C1="$C1" C2="$C2" C3="$C3" C4="$C4" BASE="${BASE:-$LEGACY_BASE}" \
    TPL_DIR="$TPL_DIR" BTOP_THEME="$BTOP_THEME" HYPRLOCK_CONF="$HYPRLOCK_CONF" \
    FASTFETCH_CFG="$FASTFETCH_CFG" COLORS_SH="$COLORS_SH" \
    MAKO_CFG="$MAKO_CFG" ALACRITTY_COLORS="$ALACRITTY_COLORS" NIRI_COLORS="$NIRI_COLORS" \
    python3 - "$@" <<'PY'
import os, colorsys, re

def hex2rgb(h): h=h.lstrip('#'); return tuple(int(h[i:i+2],16) for i in (0,2,4))
def rgb2hex(r): return '#%02x%02x%02x' % tuple(max(0,min(255,round(x))) for x in r)
def _hsv(h):
    r,g,b=[x/255 for x in hex2rgb(h)]; return colorsys.rgb_to_hsv(r,g,b)
def _back(hue,s,v):
    r,g,b=colorsys.hsv_to_rgb(hue,max(0,min(1,s)),max(0,min(1,v))); return rgb2hex((r*255,g*255,b*255))
def lighter(h,f):                      # ~ Qt.lighter: scale value, ease saturation as it clamps
    hue,s,v=_hsv(h); nv=v*f
    if nv>1: s=s/ (nv); nv=1.0
    return _back(hue,s,nv)
def darker(h,f):
    hue,s,v=_hsv(h); return _back(hue,s,v/f)
def sgr(h): r,g,b=hex2rgb(h); return "38;2;%d;%d;%d"%(r,g,b)

c1=os.environ['C1']; c2=os.environ['C2']; c3=os.environ['C3']; c4=os.environ['C4']
base=os.environ['BASE']
P=dict(base=base, base_raised=lighter(base,1.35),
    accent=c1, accent_bright=lighter(c1,1.30), accent_dim=darker(c1,1.45),
    accent_muted=darker(c1,1.95), surface_tint=darker(c1,4.20),
    blue=c2, blue_bright=lighter(c2,1.30), cyan=c3, teal=c4,
)

# --- hyprlock + fastfetch: substitute @TOKEN@ in the templates --------------
def render(tpl, dst, repl):
    with open(tpl) as f: s=f.read()
    for k,v in repl.items(): s=s.replace(k,v)
    d=os.path.dirname(dst)
    if d: os.makedirs(d, exist_ok=True)
    # never write through a symlink into the repo
    if os.path.islink(dst): os.unlink(dst)
    with open(dst,'w') as f: f.write(s)

tpl=os.environ['TPL_DIR']
# hyprlock wants colours as rgba(rrggbbaa) — no '#', alpha as the last byte.
def rgba(h, a='ff'): return 'rgba(%s%s)' % (h.lstrip('#'), a)
render(os.path.join(tpl,'hyprlock.conf.tmpl'), os.environ['HYPRLOCK_CONF'],
       {'@ACCENT_RGBA@': rgba(P['accent']),
        '@ACCENT_BRIGHT_RGBA@': rgba(P['accent_bright']),
        '@ACCENT_EDGE_RGBA@': rgba(P['accent'], '99'),     # input pill outline
        '@BASE_RGBA@': rgba(P['base']),
        '@BASE_FILL_RGBA@': rgba(P['base'], 'b3'),          # input pill fill
        '@HOME@': os.environ['HOME']})
render(os.path.join(tpl,'fastfetch-config.jsonc.tmpl'), os.environ['FASTFETCH_CFG'],
       {'@ACCENT_SGR@': sgr(P['accent']), '@CYAN_SGR@': sgr(P['cyan']),
        '@BLUE_SGR@': sgr(P['blue']), '@HOME@': os.environ['HOME']})

# niri: a gradient focus ring (accent → c2) round the focused window only. The
# profile fragments end with `include optional=true "colors.kdl"`, and niri
# merges an included layout{} field by field and live-reloads included files.
d=os.path.dirname(os.environ['NIRI_COLORS']); os.makedirs(d, exist_ok=True)
if os.path.islink(os.environ['NIRI_COLORS']): os.unlink(os.environ['NIRI_COLORS'])
with open(os.environ['NIRI_COLORS'],'w') as f:
    f.write(f"""// GENERATED by rice-theme — the focus ring in the active palette.
// Included by config.full.kdl / config.light.kdl; edit rice-theme, not this.
layout {{
    focus-ring {{
        on
        width 2
        active-gradient from="{P['accent']}" to="{P['blue']}" angle=45 in="oklch shorter hue"
        // Only the focused window gets a ring, not the active one on other outputs.
        inactive-color "#00000000"
        urgent-color "{P['accent_bright']}"
    }}
}}
""")
# mako: notifications sit on the theme base (translucent), accent progress bar.
render(os.path.join(tpl,'mako-config.tmpl'), os.environ['MAKO_CFG'],
       {'@BASE@': P['base'], '@ACCENT@': P['accent']})

# alacritty: only the background follows the theme (the ANSI palette is NOT
# themed, CLAUDE.md §13). alacritty.toml imports this file and live-reloads it.
d=os.path.dirname(os.environ['ALACRITTY_COLORS']); os.makedirs(d, exist_ok=True)
with open(os.environ['ALACRITTY_COLORS'],'w') as f:
    f.write("# generated by rice-theme — imported by alacritty.toml\n"
            "[colors.primary]\nbackground = \"%s\"\n" % P['base'])

# --- btop sanganak.theme: emit the whole thing (it's all colour) -------------
def ramp(base, lo=1.7, hi=1.30): return (darker(base,lo), darker(base,1.18), base) if hi==1.30 else (darker(base,lo), base, lighter(base,hi))
acc_lo,acc_mid,acc_hi = darker(P['accent'],1.7), P['accent'], P['accent_bright']
btop=f"""# sanganak — generated by `rice-theme`. Edit the THEME (4 colours), not this.
theme[main_bg]=""
theme[main_fg]="#f4f4f6"
theme[title]="#f4f4f6"
theme[hi_fg]="{P['accent']}"
theme[selected_bg]="{P['accent']}"
theme[selected_fg]="{P['base']}"
theme[inactive_fg]="#5e5e66"
theme[graph_text]="#f4f4f6"
theme[meter_bg]="{P['base_raised']}"
theme[proc_misc]="{P['accent']}"
theme[cpu_box]="{P['accent']}"
theme[mem_box]="{P['blue']}"
theme[net_box]="{P['teal']}"
theme[proc_box]="{P['accent']}"
theme[div_line]="#2a2a35"
theme[temp_start]="{P['accent_dim']}"
theme[temp_mid]="{P['accent']}"
theme[temp_end]="{P['cyan']}"
theme[cpu_start]="{P['accent_dim']}"
theme[cpu_mid]="{P['accent']}"
theme[cpu_end]="{P['accent_bright']}"
theme[free_start]="{darker(P['teal'],1.7)}"
theme[free_mid]="{darker(P['teal'],1.18)}"
theme[free_end]="{P['teal']}"
theme[cached_start]="{darker(P['blue'],1.7)}"
theme[cached_mid]="{darker(P['blue'],1.18)}"
theme[cached_end]="{P['blue']}"
theme[available_start]="{darker(P['cyan'],1.7)}"
theme[available_mid]="{darker(P['cyan'],1.18)}"
theme[available_end]="{P['cyan']}"
theme[used_start]="{P['accent_dim']}"
theme[used_mid]="{P['blue']}"
theme[used_end]="{P['cyan']}"
theme[download_start]="{P['accent_dim']}"
theme[download_mid]="{P['accent']}"
theme[download_end]="{P['accent_bright']}"
theme[upload_start]="{darker(P['teal'],1.7)}"
theme[upload_mid]="{darker(P['teal'],1.18)}"
theme[upload_end]="{P['teal']}"
theme[process_start]="#5e5e66"
theme[process_mid]="{P['accent']}"
theme[process_end]="{P['accent_bright']}"
"""
# write btop via the same de-symlink helper the shell uses (handled in bash)
with open('/tmp/.rice-btop-theme','w') as f: f.write(btop)

# --- zsh prompt colours -----------------------------------------------------
with open(os.environ['COLORS_SH'],'w') as f:
    f.write("# generated by rice-theme — sourced by ~/.zshrc\n")
    for k in ('accent','accent_bright','accent_dim','accent_muted','blue','blue_bright','cyan','teal'):
        f.write('export RICE_%s="%s"\n' % (k.upper(), P[k]))
PY

    # btop theme written to a tmp file by python; place it (de-symlinking).
    write_real "$BTOP_THEME" < /tmp/.rice-btop-theme && rm -f /tmp/.rice-btop-theme

    # The lock screen and fastfetch draw the stock Arch logo themselves now
    # (hyprlock label glyph, fastfetch builtin); drop the old chip renders.
    rm -f "$HOME/.config/hypr/sanganak-logo.png" "$HOME/.config/fastfetch/sanganak-logo.ansi"

    # mako has no file watch; reload it if it's running.
    command -v makoctl >/dev/null 2>&1 && makoctl reload >/dev/null 2>&1 || true

    # ly's /etc/ly/config.ini is root-owned. 07-services.sh installs a sudoers
    # rule letting the wheel group run exactly `theme-ly` (no arguments; it
    # reads ~/.config/rice/colors) without a password, so the login screen
    # follows every switch. Without the rule, sudo -n just fails and the drift
    # reminder below names the login screen instead.
    [[ -x /usr/local/bin/theme-ly ]] && sudo -n /usr/local/bin/theme-ly >/dev/null 2>&1 || true

    # Zen (the default browser): workspace 1 takes c1, workspace 2 takes c2.
    # Zen only reads them at startup, so with Zen open this queues the change
    # for when it closes (scripts/zen-theme.py).
    command -v zen-theme >/dev/null 2>&1 && zen-theme apply >/dev/null 2>&1 || true
}

# ---- wallpaper theme (pywal) --------------------------------------------------
current_wallpaper() { [[ -r "$WALLPAPER_CURRENT" ]] && head -n1 "$WALLPAPER_CURRENT" || true; }

# Run pywal on the wallpaper and map its colours onto C1..C4 + BASE. Returns 1
# (globals untouched) when pywal or a wallpaper is missing, or wal fails.
#   c1   the most vivid of pywal's six image colours, saturation lifted a little
#        so the accent still reads on the black bezel
#   c2-4 the remaining colours picked greedily for the biggest difference from
#        those already chosen, brightened enough to read on black
#   base pywal's background hue, darkened to the rice's near-black
wal_palette() {
    local img="${1:-}" out
    [[ -n "$img" ]] || img="$(current_wallpaper)"
    command -v wal >/dev/null 2>&1 || { c_err "pywal is not installed (yay -S python-pywal16)"; return 1; }
    [[ -n "$img" && -r "$img" ]] || { c_err "no wallpaper to take colours from (set one with wallpaper-next)"; return 1; }
    # -n: wallpaper is ours (swaybg/swww)  -s -t: don't recolour open terminals or
    # ttys (alacritty's ANSI palette is not themed)  -e: no gtk/xrdb/i3 reloads.
    wal -i "$img" -n -s -t -e -q >/dev/null 2>&1 || { c_err "wal failed on $img"; return 1; }
    out="$(python3 - "$WAL_CACHE/colors.json" <<'PY'
import json, colorsys, sys

def hex2rgb(h): h=h.lstrip('#'); return tuple(int(h[i:i+2],16)/255 for i in (0,2,4))
def rgb2hex(r): return '#%02x%02x%02x' % tuple(max(0,min(255,round(x*255))) for x in r)
def hsv(h): return colorsys.rgb_to_hsv(*hex2rgb(h))
def fromhsv(h,s,v): return rgb2hex(colorsys.hsv_to_rgb(h%1, max(0,min(1,s)), max(0,min(1,v))))

def shape(c, smin, vmin, vmax):
    h,s,v = hsv(c)
    if s > 0.04: s = max(s, smin)                  # greys stay grey
    return fromhsv(h, s, min(max(v, vmin), vmax))

def dist(a, b):
    (h1,s1,v1),(h2,s2,v2) = hsv(a), hsv(b)
    dh = min(abs(h1-h2), 1-abs(h1-h2)) * 2         # hue gap, 0..1
    return dh * min(s1, s2) * 4 + abs(s1-s2) + abs(v1-v2)

d = json.load(open(sys.argv[1]))
cands = list(dict.fromkeys(d['colors']['color%d' % i].lower() for i in range(1, 7)))
c1 = max(cands, key=lambda c: hsv(c)[1] * (0.6 + hsv(c)[2]))
chosen, pool = [c1], [c for c in cands if c != c1]
while len(chosen) < 4 and pool:
    nxt = max(pool, key=lambda c: min(dist(c, x) for x in chosen))
    chosen.append(nxt); pool.remove(nxt)
while len(chosen) < 4:                             # near-monochrome wallpapers
    h,s,v = hsv(chosen[-1]); chosen.append(fromhsv(h + 0.12, s, v))
h,s,v = hsv(d['special']['background'])
print(' '.join([shape(chosen[0], 0.38, 0.78, 0.96)]
               + [shape(c, 0.22, 0.66, 0.94) for c in chosen[1:]]
               + [fromhsv(h, min(s, 0.35), 0.075)]))
PY
)" || { c_err "couldn't read pywal's colours"; return 1; }
    read -r C1 C2 C3 C4 BASE <<<"$out"
    [[ "$C1$C2$C3$C4$BASE" =~ ^(#[0-9a-f]{6}){5}$ ]] || { c_err "pywal mapping gave: $out"; return 1; }
}

# The live palette back into C1..C4 + BASE (re-render after a template change).
load_live_palette() {
    local L
    [[ -r "$COLORS_FILE" ]] || return 1
    mapfile -t L < <(grep -oE '#[0-9a-fA-F]{6}' "$COLORS_FILE")
    [[ ${#L[@]} -ge 4 ]] || return 1
    C1="${L[0]}" C2="${L[1]}" C3="${L[2]}" C4="${L[3]}" BASE="${L[4]:-}"
}

cmd_wal() {
    local img="${1:-}"
    mkdir -p "$RICE_DIR"
    echo "wal" > "$ACTIVE_FILE"
    if wal_palette "$img"; then
        printf '%s\n' "$C1" "$C2" "$C3" "$C4" "$BASE" > "$WAL_PALETTE"
        apply_palette
        c_info "theme → wallpaper ($C1 $C2 $C3 $C4 base $BASE)"
        return 0
    fi
    # pywal or a wallpaper isn't there yet (fresh install before Finish setup /
    # 09-wallpapers). Stay in wallpaper mode, so the next wallpaper change picks
    # it up, and render the configs from the live palette (else deccan).
    load_live_palette || load_theme_file "$THEMES_DIR/$DEFAULT_THEME.theme"
    apply_palette
    c_info "wallpaper theme selected; using $C1 $C2 $C3 $C4 until pywal can run"
}

# ---- subcommands ------------------------------------------------------------
cmd_set() {
    local name="$1"
    [[ "$name" == "wal" ]] && { cmd_wal; return; }
    load_theme_file "$THEMES_DIR/$name.theme"
    apply_palette
    echo "$TNAME" > "$ACTIVE_FILE"
    c_info "theme → $TNAME ($C1 $C2 $C3 $C4${BASE:+ base $BASE})"
}

cmd_next() {
    local cur all arr i n; cur="$(active_name)"
    mapfile -t arr < <(themes_list)
    # The wallpaper theme leads the cycle once pywal is installed.
    command -v wal >/dev/null 2>&1 && arr=("wal" "${arr[@]}")
    [[ ${#arr[@]} -gt 0 ]] || die "no themes in $THEMES_DIR"
    n=${#arr[@]}; i=0
    for ((j=0;j<n;j++)); do [[ "${arr[$j]}" == "$cur" ]] && i=$j; done
    local nxt="${arr[$(((i+1)%n))]}"
    cmd_set "$nxt"
    [[ "$nxt" == "wal" ]] && nxt="wallpaper"
    command -v notify-send >/dev/null && \
        notify-send -t 2500 "Theme → $nxt" "$C1  $C2  $C3  $C4" || true
}

cmd_create() {
    local name="$1" c1="$2" c2="$3" c3="$4" c4="$5" base="${6:-}"
    [[ "$c1$c2$c3$c4" =~ ^(#[0-9a-fA-F]{6}){4}$ ]] || die "need 4 #rrggbb colours"
    [[ -z "$base" || "$base" =~ ^#[0-9a-fA-F]{6}$ ]] || die "base must be #rrggbb"
    mkdir -p "$THEMES_DIR"
    cat > "$THEMES_DIR/$name.theme" <<EOF
# rice theme — c1=accent/hero c2=blue c3=cyan c4=teal (shades derived by rice-theme)
name=$name
c1=$c1
c2=$c2
c3=$c3
c4=$c4
EOF
    [[ -n "$base" ]] && echo "base=$base" >> "$THEMES_DIR/$name.theme"
    c_info "created theme '$name'"
}

cmd_save() {  # snapshot current live palette under a new name
    local name="$1"
    [[ -r "$COLORS_FILE" ]] || die "no live palette yet — run 'rice-theme set <name>' first"
    mapfile -t L < <(grep -oE '#[0-9a-fA-F]{6}' "$COLORS_FILE")
    [[ ${#L[@]} -ge 4 ]] || die "live palette incomplete"
    cmd_create "$name" "${L[0]}" "${L[1]}" "${L[2]}" "${L[3]}" "${L[4]:-}"
}

cmd_list() {
    local cur; cur="$(active_name)"
    if command -v wal >/dev/null 2>&1; then
        if [[ "$cur" == "wal" ]]; then printf '  ● wal — follows the wallpaper (active)\n'
        else printf '  ○ wal — follows the wallpaper\n'; fi
    fi
    while read -r t; do
        [[ -z "$t" ]] && continue
        if [[ "$t" == "$cur" ]]; then printf '  ● %s (active)\n' "$t"; else printf '  ○ %s\n' "$t"; fi
    done < <(themes_list)
}

main() {
    local cmd="${1:-status}"; shift || true
    case "$cmd" in
        status) active_name; echo ;;
        list)   cmd_list ;;
        set)    [[ $# -ge 1 ]] || die "usage: rice-theme set <name>"; cmd_set "$1"; surfaces_sync_reminder ;;
        apply-colors)  # apply 4 colours LIVE without saving a named theme
                [[ $# -eq 4 || $# -eq 5 ]] || die "usage: rice-theme apply-colors c1 c2 c3 c4 [base]"
                [[ "$1$2$3$4" =~ ^(#[0-9a-fA-F]{6}){4}$ ]] || die "need 4 #rrggbb colours"
                [[ -z "${5:-}" || "$5" =~ ^#[0-9a-fA-F]{6}$ ]] || die "base must be #rrggbb"
                C1="$1" C2="$2" C3="$3" C4="$4" BASE="${5:-}"; apply_palette
                echo "custom" > "$ACTIVE_FILE"
                c_info "applied custom palette (NOT saved — 'rice-theme save <name>' to keep it)"
                surfaces_sync_reminder ;;
        next)   cmd_next; surfaces_sync_reminder ;;
        create) [[ $# -eq 5 || $# -eq 6 ]] || die "usage: rice-theme create <name> c1 c2 c3 c4 [base]"; cmd_create "$@" ;;
        save)   [[ $# -ge 1 ]] || die "usage: rice-theme save <name>"; cmd_save "$1" ;;
        apply)  local a; a="$(active_name)"; [[ -n "$a" ]] || a="$DEFAULT_THEME"; cmd_set "$a" ;;
        wal)    cmd_wal "${1:-}"; surfaces_sync_reminder ;;
        wal-sync)  # from wallpaper-init / wallpaper-next: only in wallpaper mode
                [[ "$(active_name)" == "wal" ]] || exit 0
                wal_palette "${1:-}" || exit 0
                printf '%s\n' "$C1" "$C2" "$C3" "$C4" "$BASE" > "$WAL_PALETTE"
                apply_palette ;;
        *) die "unknown command: $cmd (try: status|list|set|next|create|save|apply|wal)" ;;
    esac
}
main "$@"
