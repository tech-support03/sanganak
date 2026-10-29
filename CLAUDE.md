# Arch Linux Rice — Build Spec for Claude Code

> **Read this end-to-end before touching anything.** This is a single-shot
> install spec for a daily-driver Arch setup. The user is reinstalling
> their whole system based on this — **it has to work first try, no
> hiccups.** If something is ambiguous, **stop and ask**, do not guess.
> Do not substitute packages or compositors without explicit approval.

The visual reference is `arch rice v5 daily-driver.html` (open it in a
browser to see exactly what hover/animation/translucency behavior is
expected). Match it precisely.

---

## 0. Non-negotiables

- **No Hyprland.** Compositor is **Niri** (scrollable-tiling Wayland).
- **Dark mode only.** No light theme code paths.
- **Every interactive surface must animate** (hover, click, expand,
  open/close, focus change). Default duration 180–320ms, ease
  `cubic-bezier(.2,.85,.25,1)`. No instant state changes.
- **Translucent surfaces** on every system piece: lock screen, terminal,
  notifications, launcher, power flyout. Background alpha ~0.32, blur
  28–32px, saturation 1.4. **Exception (user's call, 2026-10-27):** the edge
  bar, the media notch and the bar's panels are solid bezel black (`#000`) —
  they read as part of the monitor edge, carried over from the user's Omarchy
  setup.
- **Minimum packages.** If a feature can be done by an existing
  service, don't add another. List below is curated — don't expand it
  without asking.
- **No filler.** No placeholder widgets, no "TODO" panels shipped to
  the user. Either implement or leave out.
- **12-hour clocks everywhere.** All clock surfaces (sidebar, top bar
  dashboard, lock screen, OSD) render time as `h:MM` with an `AM`/`PM`
  suffix. Never `HH:MM` 24-hour.

---

## 1. Stack

| Layer | Choice | Why |
|---|---|---|
| Compositor | **Niri** | Scrollable tiling, built-in animations, blur, no Hyprland |
| Shell / bar / widgets / launcher / power flyout | **Quickshell** | QML, full custom UI (Caelestia uses this) |
| Lock screen | **hyprlock** | Parallel fingerprint + password unlock; superseded gtklock (which could only do them in sequence). Quickshell's WlSessionLock proved unstable |
| Notifications | **mako** | DBus daemon; Quickshell custom widget not yet built |
| Wallpaper | **swaybg** (or **swww** if present) | swaybg is the default; wallpaper-init.sh prefers swww when installed |
| Audio | **PipeWire + WirePlumber** | Standard |
| Network | **iwd** (wifi) + **systemd-networkd** (wired) | NetworkManager removed — it fought iwd. Quickshell queries iwd over DBus + `ip`. See §Networking |
| Bluetooth | **BlueZ + bluetuith** (CLI) | Quickshell shows status via DBus |
| Idle / autolock | _none_ | Lock is manual-only (`Mod+L`); system never auto-sleeps |
| Screensaver | **tte** (`python-terminaltexteffects`, AUR) via `sanganak-screensaver` | Omarchy-style; Quickshell's own `IdleMonitor` starts it after 2.5 min idle — no idle daemon, never locks (§6) |
| Theme from wallpaper | **pywal** (`python-pywal16`, AUR — the maintained fork; same `wal` CLI) | `rice-theme wal` maps pywal's colours onto the 4-colour palette (§13) |
| Terminal | **alacritty** | GPU-accelerated, Wayland-native |
| Screenshot | **niri built-in** (`screenshot` action) | Interactive region/window/output picker, saves to `~/Pictures/Screenshots/` |
| Clipboard history | **wl-clipboard + cliphist** | |
| Login manager | **ly** | TUI greeter on tty1, no GUI dep |
| File manager | **nautilus** | Familiar (ChromeOS/macOS-ish) |
| Fonts | **SF Pro (UI, `apple-fonts` AUR) + JetBrains Mono Nerd Font (mono)** | System default via `~/.config/fontconfig/fonts.conf`; Noto Sans Devanagari covers Devanagari, Noto Sans is the fallback if apple-fonts fails to build |
| Icons | **Papirus-Dark** (system) | |

> Quickshell owns launcher, power flyout, both bars, and (eventually)
> notifications. The approved lock surface is **hyprlock** — it runs PARALLEL
> auth (PAM password + fprintd fingerprint at once), which gtklock structurally
> can't (single blocking PAM conversation), and Quickshell's WlSessionLock was
> unstable. hyprlock is standalone (ext-session-lock), so it does **not** drag
> in Hyprland. Do not pull in waybar, eww, ags, dunst, swaylock, rofi, wofi,
> fuzzel, wlogout, swayidle. (hyprlock is the one Hypr-ecosystem exception, and
> only for the lock surface — no hyprland/hyprpaper/hypridle/etc.)

---

## 2. Packages

Authoritative lists live in **`packages/`** (see `packages/README.md`), shared
by every install path:

| List | What | Installed by |
|---|---|---|
| `desktop.txt` | core session: niri, quickshell, hyprlock, ly, mesa + Vulkan (radeon / intel / swrast), pipewire, iwd, bluez, fonts, zsh, gum/fzf, VM guest tools | ISO pacstrap (offline) · `install.sh` module 01 |
| `aur-offline.txt` | `yay-bin`, prebuilt into the ISO | ISO · module 02 |
| `apps.txt` | chromium, discord, nautilus, nwg-displays, cava, openrgb, ddcutil, … + gaming: steam, gamescope, gamemode, mangohud, lib32 Vulkan | `sanganak-finish-setup` · module 01 |
| `aur.txt` | spotify, wooting-bg-service, python-pywal16, python-terminaltexteffects, claude-code, apple-fonts (non-fatal) | `sanganak-finish-setup` · module 03 |

`[multilib]` is enabled by the installer (steam, lib32 drivers). NVIDIA gets
`nvidia-open-dkms` + utils, chosen at install time (`modules/lib.sh:
gpu_extras`). Don't add packages anywhere but these lists.

### Services to enable
```bash
systemctl enable --now iwd systemd-networkd bluetooth seatd
systemctl enable ly@tty1.service           # greeter on tty1
systemctl --user enable --now pipewire pipewire-pulse wireplumber kanshi
```
> **Do NOT enable `systemd-resolved`.** DNS is a static `/etc/resolv.conf`
> (the daily-driver layers Cloudflare WARP over it); resolved would seize DNS
> and re-break the school content-filter path. See §Networking.

### Networking (iwd + systemd-networkd)

NetworkManager is **gone** — it fought iwd on this hardware. The split is:

- **Wifi → iwd, standalone.** iwd does association *and* its own DHCP/routes
  (`/etc/iwd/main.conf` → `[General] EnableNetworkConfiguration=true`). It does
  **not** manage DNS (`[Network] NameResolvingService=none`).
- **Wired → systemd-networkd**, the wired NIC only (`/etc/systemd/network/20-wired.network`,
  `[Match] Name=en*`). DHCP for address + routes only (`UseDNS=no`).
  `RouteMetric=100` makes a plugged-in cable **auto-win** over wifi (~308);
  `RequiredForOnline=no` so an unplugged cable never stalls boot. networkd
  leaves `wlan0` *unmanaged* — iwd keeps it.
- **DNS → static `/etc/resolv.conf`** (`1.1.1.1`/`8.8.8.8`) with WARP on top.
  No daemon rewrites it. **No systemd-resolved.** The one writer is
  `sanganak-dns`, run only when the user picks a provider in the network panel
  (Omarchy's choices: **DHCP / Cloudflare / Google / Custom**). DHCP takes the
  DNS option from networkd's DHCPv4 lease on wired; on Wi-Fi iwd discards the
  offered servers, so the gateway stands in, and the panel re-applies DHCP when
  the gateway changes. `/etc/sudoers.d/40-sanganak-dns` (07-services.sh) lets
  wheel run the three fixed providers passwordless; Custom asks for a password
  in a floating terminal.
- **Manual override:** a polkit rule (`/etc/polkit-1/rules.d/50-networkd-links.rules`,
  action `org.freedesktop.network1.manage-links`) lets the active session run
  `networkctl up/down` passwordless, so the flyout's Ethernet toggle can force
  wifi without unplugging.

Quickshell's `services/Network.qml` is the single source of truth for the UI:
it queries iwd over DBus via `busctl` (scan list, saved networks, radio power,
active connection) and reads `ip` for routes / local IP / the wired NIC. **No
`nmcli`/`nmtui` anywhere** — actions shell out to `iwctl` (wifi) and
`networkctl` (wired). All three `/etc` files above are written by
`modules/07-services.sh` (and seeded in the ISO path by
`iso-stage/04-chroot-config.sh`). The panel's **speed test** is
`sanganak-speedtest down|up` — curl only, four streams, live Mbps from the
uplink's byte counter, averaged from a 1 s warm-up until the first stream
completes (`services/SpeedTest.qml`). Server: speed.cloudflare.com, which
rate-limits big transfers per IP (HTTP 429 for up to an hour), so a run sends
few requests (a HEAD probe, then ≤ 2 transfers per stream); a refused download
falls back to the fastest of a few public test-file mirrors (Vultr, OVH), and
the panel names the server used. DNS state is `services/Dns.qml`.

---

## 3. File tree (final state of `~/.config`)

```
~/.config/
├── niri/
│   ├── config.kdl                  # see §4 (generated by rice-profile)
│   ├── colors.kdl                  # focus ring in the theme colours (generated by rice-theme)
│   └── monitor.kdl                 # written by nwg-displays
├── quickshell/                    # → dotfiles/quickshell (see §5)
│   ├── shell.qml                   # entry point
│   ├── theme/Theme.qml             # tokens (colors, radii, bezel, anim) — live from ~/.config/rice/colors
│   ├── bars/EdgeBar.qml            # right-edge bezel bar + its panels; widgets/ = its icons
│   ├── bars/TopBar.qml             # media notch (waveform while playing)
│   ├── panels/                     # audio, network, bluetooth, calendar, weather, display, …
│   ├── ui/                         # Panel card, BarButton, Slider, Toggle, ListRow, TextBox
│   ├── overlays/                   # Launcher (Mod+Space), PowerFlyout (Mod+Esc), ThemePicker, RgbControl, VolumeOSD, Screensaver (idle trigger)
│   ├── services/                   # Niri, Panels, Network (iwd), Bluetooth, SysStats, Weather, Updates, Agents, …
│   └── cava.conf                   # config for the waveform
├── alacritty/alacritty.toml
├── mako/config                     # notification daemon
├── cava/config
├── hypr/hyprlock.conf              # lock screen (Mod+L); generated by rice-theme
├── kanshi/config                   # display profiles, started via systemd --user
├── fontconfig/fonts.conf           # SF Pro = sans-serif default, JetBrains Mono = monospace
├── gtk-3.0/ gtk-4.0/               # dark theme
├── btop/  fastfetch/               # CLI utilities
```

Lock is **hyprlock** (`~/.config/hypr/hyprlock.conf`, generated by rice-theme),
not Quickshell (WlSessionLock was unstable) and not gtklock (which couldn't run
fingerprint + password in parallel). Login is **ly** on tty1
(`/etc/ly/config.ini`), not greetd. Launcher and power flyout are Quickshell
overlays — no fuzzel/rofi/wlogout.

Skeletons for `niri/config.kdl`, `alacritty/alacritty.toml`,
`quickshell/Theme.qml`, and `quickshell/shell.qml` are already in this
project — use them as starting points and flesh out the QML widgets to
match the HTML mockup.

---

## 4. Niri behavior (config.kdl highlights)

- **No window decorations.** The focused window (only that one) gets a 2px
  **gradient focus ring**, accent → c2 at 45°, from `~/.config/niri/colors.kdl`
  — generated by `rice-theme` on every theme switch and included at the end of
  both profile fragments (`include optional=true`; niri merges an included
  `layout {}` field by field and live-reloads it).
- **Gaps:** outer 12px, inner 8px.
- **Default rule:** `opacity 0.95` on `[term, file-manager,
  Quickshell-floating]` for the translucent-system look. **Do not
  blanket-opacity Chrome, Spotify, Discord, Steam, video apps** — they
  must stay opaque for legibility **while focused**.
- **Unfocused fade (user's call, 2026-10-28):** in the `full` profile every
  unfocused window, browsers / Discord / Steam included, drops to `opacity 0.85`
  (`match is-focused=false`, after the per-app rules). Games (`gamescope`,
  `steam_app_*`) and the screensaver are pinned back to 1.0. While a layer
  surface holds the keyboard (launcher, a panel, the power menu, a pinned bar
  under the pointer) no window is focused, so all of them fade. `light` keeps
  everything opaque.
- **Animations:** keep niri's defaults but bump
  `window-open` and `workspace-switch` curves to feel slightly
  springy. Reference: niri's `animations { ... }` block.
- **Keybinds (must match):** every bind carries a `hotkey-overlay-title` —
  `sanganak-keybindings` and niri's own overlay show it, so a new bind needs one.

| Bind | Action |
|---|---|
| Super+Return | alacritty |
| Super+Shift+A | Claude Code in its own terminal (`alacritty --class sanganak.claude -e claude`), Omarchy-style, started in `~/arch-setup` (home if missing) |
| Super+Space | toggle Quickshell launcher (`qs ipc call launcher toggle`) |
| Super+Escape | toggle power flyout (`qs ipc call power toggle`) |
| Super+Alt+Space | sanganak menu panel (packages, updates, keybindings, theme, …) |
| Super+K | keybindings list (`sanganak-keybindings`, read from the live config) |
| Super+L | lock — `pgrep -x hyprlock \|\| hyprlock` |
| Super+W | close window |
| Super+F | maximize column |
| Super+Shift+F | fullscreen window |
| Super+R | reset window height |
| Super+Shift+B | next wallpaper |
| Super+1..9 | switch to workspace 1..9 |
| Super+Shift+1..3 | move window to workspace 1..3 |
| Super+Arrow | focus column/window |
| Super+Shift+Arrow | move column/window |
| Print | screenshot (niri built-in interactive UI) |
| XF86Audio* | playerctl / wpctl |
| XF86MonBrightness* | brightnessctl |

- **Autostart** (`spawn-at-startup`): `wallpaper-init` (swaybg or swww),
  `quickshell`, `mako`, `wl-paste --watch cliphist store` (text+image),
  `polkit-gnome-authentication-agent-1`, `xwayland-satellite`.
  No idle daemon — lock and suspend are user-initiated only.
- **Wallpaper:** `~/Pictures/Wallpapers` (filled by 09-wallpapers.sh: the
  ISO's bundled set, else five downloads), seeded by `wallpaper-init`; cycle
  with `wallpaper-next` (bound to Super+Shift+B; `wallpaper-next IMAGE` shows
  one). `wallpaper add|rm|set|open` manages the folder (removals go to the
  Trash) — the sanganak menu has Add / Remove current / Folder entries.

---

## 5. Quickshell behavior (must-haves)

This is the heaviest piece — keep it modular and **read the
Quickshell docs first** (`quickshell.outfoxxed.me`). Key APIs:
`PanelWindow`, `MprisPlayer`, `Process`, `FileView`, `DBusConnection`.

### 5.1 Edge bar (`bars/EdgeBar.qml`) — replaces the old SideBar

Rewritten from the user's Omarchy `arjun.bar` (no Omarchy code, no Hyprland):

- **Right edge**, one per monitor. At rest a 2px input strip; touching the
  edge slides out a **solid black band** (`Theme.barSize` 56px) the full height
  of the screen, with **concave fillets** into the top and bottom edges; while
  it is out, black corner pieces round the two far corners, so all four screen
  corners share `Theme.screenRadius` (24).
- **Pin:** click empty band space → stays out and reserves its width
  (`ExclusionMode.Normal`); a chevron at the very bottom (below power) or
  **Escape** (while the pointer is on it) unpins. It also stays out while one
  of its panels is open.
- **Sections** top → bottom: Arch logo (click: fastfetch, right: menu),
  niri workspaces of *that* output · indicators (DnD, recording), keyboard
  layout (only with >1), 12-hour vertical clock, weather, menu, updates
  (only when pending) · tray drawer (every tray icon — Discord, wooting, … —
  behind a "•••" handle that slides them out on hover; the handle shows an
  accent dot while a hidden icon carries an unread dot — `TrayDrawer.qml`),
  sysmon meters, attention tray (an icon appears here only while its SNI status
  is NeedsAttention), display, AI agents (hidden until
  usage exists), bluetooth, network, audio (wheel = volume), battery
  (**laptop only**, `Services.Battery.present` — never on the desktop), power,
  then the unpin chevron while pinned. Every status icon is a solid glyph in
  `fg0` (dimmed `fg3` when off) — power included; only alerts use `danger`.
  Tray icons draw through a Canvas: dark single-colour icons (wooting's) are
  repainted white for the black bar, and Discord's baked-in red unread dot is
  repainted in the accent. blueman's own tray icon is off (its `StatusIcon`
  plugin is disabled via gsettings in 08-link-dotfiles.sh); the applet keeps
  running as the pairing agent.
- **Panels** (`panels/*`, card = `ui/Panel.qml`): audio mixer (outputs, inputs,
  per-app), network (wired override, speed test, DNS provider, iwd list with
  inline password), bluetooth, calendar (ISO weeks), weather (hourly + 3-day,
  settable location), display (Omarchy's layout: brightness of that screen with
  its "mood" — brightnessctl / DDC/CI — UI text size, valid scales, every
  display with mode / refresh / VRR and an on/off click; `services/Display.qml`;
  wheel on the bar icon = brightness), battery + power
  profiles, AI agents (limits, tokens by day / model), system detail, updates,
  sanganak menu. One open at a time (`services/Panels.qml`); open from the bar
  or `qs ipc call panel toggle <id>`.

### 5.2 Media notch (`bars/TopBar.qml`) — Omarchy `arjun.topbar`

Invisible at rest. While media plays, a floating cava waveform (no background;
simulated when cava hears nothing, skipped in the light profile). Hovering the
top-centre edge opens a black notch hanging from the top edge (concave top
corners): album art, source (click raises the app through niri), title /
artist, prev / play / next, progress.

Workspaces, focused window, keyboard layouts and app focusing all come from
**`services/Niri.qml`** (`niri msg --json event-stream`). Never call hyprctl.

### 5.3 LockScreen (`overlays/LockScreen.qml`)

- Full-screen `PanelWindow` with `WlrLayershell.layer: Overlay` and
  `exclusiveZone: -1`. Background: `rgba(0,0,0,0.20)` over the
  desktop with backdrop blur 28px.
- **Time** dead-center: 200px JetBrains Mono Light, tabular-nums,
  letter-spacing -0.06em. Date 22px below.
- **Password field**: pill input, blurred, accent submit button.
- **Bottom widgets** (grid 2 col, max-width 720): Weather, Now
  Playing. Subtle, no chrome dominance.
- Lock is **manual only** (`Mod+L`). No idle-based auto-lock and no
  auto display-off; the system stays awake until the user suspends or
  powers it down via the Quickshell power flyout.

### 5.4 Notifications (`widgets/Notifications.qml`)

- DBus name `org.freedesktop.Notifications`.
- Popups slide in from top-right (under top bar area when
  collapsed), auto-dismiss 6s, hoverable, action buttons supported.
- Persistent stack visible in the TopBar's expanded notifications
  cell (last 5).
- Sound: optional, default off.

### 5.5 Theme tokens (`Theme.qml`)

Single source of truth — every other QML imports this.

```qml
QtObject {
    readonly property color accent: "#c5b3ff"
    readonly property color fg0: "#f4f4f6"
    readonly property color fg1: "#c9c9d0"
    readonly property color fg2: "#8e8e96"
    readonly property real  alpha: 0.32
    readonly property color surface: Qt.rgba(0.086, 0.086, 0.11, alpha)
    readonly property color surface2: Qt.rgba(0.11, 0.11, 0.13, alpha + 0.18)
    readonly property int   radius: 18
    readonly property int   radiusSmall: 12
    readonly property int   blur: 32
    readonly property int   animFast: 180
    readonly property int   animMed: 240
    readonly property int   animSlow: 380
    readonly property var   easeOut: [0.2, 0.85, 0.25, 1.0]
}
```

---

## 6. Lock / idle behavior

**Idle daemon disabled by design.** The system never auto-locks and
never auto-blanks. The only paths to a locked or sleeping machine are
user-initiated:

- `Mod+L` → `pgrep -x hyprlock || hyprlock` (config at
  `~/.config/hypr/hyprlock.conf`, generated by rice-theme)
- Quickshell power flyout → suspend / reboot / power off via `systemctl`
  (logind + polkit; no password needed for the active-session user)

The lock screen unlocks by **fingerprint OR password, in parallel**: hyprlock
runs the PAM password stack (`/etc/pam.d/hyprlock` → `auth include login`) and
an fprintd fingerprint verify at the same time — touch the sensor or type, both
are live. The on-lock **Sleep / Restart / Shut Down / Log Out** buttons are
hyprlock `onclick` labels (the Quickshell power flyout can't be used while
locked — ext-session-lock hides every other surface). fprintd's `verify` is
`allow_active=yes`, so no PAM fingerprint module is needed for the lock.

Do **not** re-add `swayidle` to `spawn-at-startup`. If lock-on-suspend
is wanted later, wire it explicitly and ask the user first.

**Screensaver (user's call, 2026-10-28)** — the one idle behaviour, and it is
neither a lock nor a blank: `overlays/Screensaver.qml` (Quickshell
`IdleMonitor`, ext-idle-notify, `respectInhibitors`) runs
`sanganak-screensaver` after **150 s** idle and `sanganak-screensaver --stop`
on the next input. It opens a fullscreen black alacritty (`sanganak.screensaver`)
per output running a random `tte` effect over the संगणक wordmark, settling on
the accent → c2 gradient; any key, pointer motion or focus change ends it. It
skips when hyprlock is up or a game (`gamescope` / `steam_app_*`) has focus.
The sanganak menu has a "Screensaver" entry to start it on demand.

---

## 7. Login manager (ly)

`ly` runs as `ly@tty1.service`. It reads installed Wayland sessions
from `/usr/share/wayland-sessions/` — niri's session file is written
by `modules/04-niri-stack.sh`.

Niri ships a `niri-session` script; if missing, write a 3-liner that
exports `XDG_CURRENT_DESKTOP=niri` and `exec niri`. Do not pull in
greetd/tuigreet/regreet — that stack was removed.

---

## 8. App-specific notes

- **Chrome:** launch with `google-chrome-stable --ozone-platform-hint=auto
  --enable-features=WaylandWindowDecorations`. Add a desktop file
  override if needed for proper icon.
- **Spotify:** runs under XWayland by default — fine. If you want
  Wayland-native, install `spotify-launcher` instead.
- **Discord:** XWayland.
- **Steam:** XWayland. Add `STEAM_FORCE_DESKTOPUI_SCALING=1.25` if
  user is on hi-dpi.
- **WhatsApp:** `whatsapp-for-linux` is electron-XWayland. If buggy
  on Niri, fall back to `zapzap-git`. Confirm with user.

---

## 9. Testing checklist (run before declaring done)

Each line must pass. If any fails, **stop and report exact error**;
do not paper over.

- [ ] `niri --validate ~/.config/niri/config.kdl` succeeds.
- [ ] `quickshell -c ~/.config/quickshell/shell.qml` starts with no
      QML errors in stderr.
- [ ] Boot → ly greeter on tty1 → log in → niri session lands with
      wallpaper visible.
- [ ] Touch the right edge → the black band slides out with filleted ends
      and the far corners rounded; it tucks away 250ms after leaving.
      Click empty band → pinned (windows move aside); Escape / chevron unpins.
- [ ] Band workspaces show only that output's niri workspaces and follow
      `Super+1..9`; clicking one focuses it on that output.
- [ ] Every band icon opens its panel next to it; Escape / click outside
      closes; only one panel open at a time.
- [ ] Start music → waveform floats at the top centre; hover the top edge →
      the notch opens with art / title / controls; clicking the source
      raises the app.
- [ ] `Super+K` lists the binds of the live config; `Super+Alt+Space` opens
      the menu, and its package / update tools open as floating terminals.
- [ ] `Super+Escape` opens power flyout; Lock / Sign out / Suspend /
      Reboot / Power off all fire (test reboot LAST).
- [ ] `Super+L` → lock screen appears, time correct, password unlocks.
- [ ] System never auto-locks and never auto-blanks; only `Mod+L` and
      the power flyout change state.
- [ ] `Print` opens niri's built-in screenshot UI; output saved to `~/Pictures/Screenshots/`.
- [ ] Notifications: `notify-send "test"` shows a mako popup on the theme base.
- [ ] Battery widget: **visible on laptop** (BAT* present, shows level +
      percent), **hidden on desktop** (no BAT* node).
- [ ] Terminal (alacritty) is translucent; Chrome / Spotify / Steam are
      opaque.
- [ ] All hover/click states animate (no instant snap anywhere).
- [ ] Focused window has the accent → c2 gradient ring; unfocused windows
      fade to 0.85 (`full`); games and the screensaver stay solid.
- [ ] `Super+Shift+A` opens Claude Code in a terminal, in `~/arch-setup`.
- [ ] `rice-theme set wal`, then `Super+Shift+B` → bars, panels, power menu,
      lock screen, mako, alacritty background, btop, fastfetch, focus ring and
      (with the sudoers rule) the ly greeter all take the new wallpaper's colours.
- [ ] Idle 2.5 min → screensaver on every output; a key or mouse move ends it.
- [ ] Discord's tray unread dot is the accent, not red.
- [ ] Close and reopen Zen after a theme switch → workspace 1 is c1, 2 is c2.
- [ ] Only one Bluetooth icon on the bar; background-service icons appear
      when hovering the "•••" handle above the system meters.
- [ ] Display panel shows brightness (wheel on its icon changes it), text
      size, scale and both displays; network panel runs a speed test and
      switches DNS (`cat /etc/resolv.conf`).

---

## 10. Install order (run as plain user with sudo, not as root)

1. Confirm `pacman -Syu` is clean.
2. Enable multilib, install pacman package list.
3. Install paru (or yay), then AUR list.
4. Enable services (see §2).
5. Drop config files in place (this project's stubs).
6. `mkdir -p ~/.config/wallpapers` and copy at least one image to
   `current.jpg`.
7. Login shell → **zsh** (chosen for fish-style autocomplete). `install.sh`
   runs `chsh -s /usr/bin/zsh` idempotently after dotfiles are linked; the rc
   is `dotfiles/zsh/.zshrc` (autosuggestions + syntax-highlighting + completion,
   all official-repo packages from `01-base-packages.sh`).
8. Reboot, log in via ly → Niri.
9. Run testing checklist §9. If anything fails, **report it** — do
   not iterate silently.

---

## 11. Hard rules for Claude Code

- **Don't deviate** from the stack without surfacing the question.
- **Don't add cute extras** (cava bars in the panel, weather radar,
  blur shaders) until everything in §9 passes.
- **Don't run `pacman -R`** on anything not installed by this spec.
- **Don't overwrite** `/etc/*` files without showing the diff first.
- **Secure Boot depends on the target type — never use the wrong one:**
  - **Bare-metal installs** (`TARGET_TYPE=ssd`): the `sbctl` path is OK —
    it enrolls our own keys into the firmware's `db` (Limine + `sbctl
    enroll-keys --microsoft`). This requires firmware **Setup Mode** and
    rewrites **PCR 7**.
  - **USB / removable installs** (`TARGET_TYPE=usb`): **MUST use the shim +
    MOK chain. Never run `sbctl enroll-keys` on a USB target.** A portable
    stick gets plugged into machines we don't own; enrolling keys into `db`
    (or clearing PK for Setup Mode) changes PCR 7 and **triggers BitLocker
    recovery** on any dual-boot/Windows host. shim (Microsoft-signed) +
    a MOK enrolled once via MokManager keeps Secure Boot **enabled** and
    leaves `db`/PK/KEK **untouched**, so BitLocker is never disturbed.
  - Rule of thumb: `TARGET_TYPE=usb` ⇒ shim+MOK; `TARGET_TYPE=ssd` ⇒ sbctl.
- **When in doubt → stop and ask.**

---

## 12. Visual profiles — `full` / `light`

The rice runs in one of two visual profiles, switchable **live, no logout**.
`full` is the default daily-driver look. `light` is for the **2014 MacBook Air
(4GB, Intel HD 5000)** — purely cosmetic/perf, **no widget is removed**.

- **Single source of truth:** the one-word file `~/.config/rice/profile`
  (`full` | `light`).
- **One command:** `rice-profile [status|full|light|toggle]`. **`Mod+Shift+P`**
  is bound to `rice-profile toggle`. (`scripts/rice-profile.sh` →
  `/usr/local/bin/rice-profile`.)
- **Boot seed:** `rice-profile-seed` runs at niri startup (first
  `spawn-at-startup`, before quickshell). It reads `rice.profile=` from the
  kernel cmdline — so the USB's GRUB entries (`…full` / `…light`, written by
  `modules/10-bootloader-shim-mok.sh`) pick the profile automatically. With no
  cmdline directive it respects the saved choice, else defaults to `full`.

**What `light` changes (and nothing else):**

| Piece | full | light |
|---|---|---|
| niri window translucency (alacritty/dialogs) | opacity 0.92–0.95 | **opaque** |
| niri shadows | soft drop shadows | **off** |
| niri animations | springs (continuous sim) | **short fixed-duration curves** |
| TopBar cava waveform | on while media plays | **skipped** (no cava subproc / 30fps loop) |
| SystemMonitor poll | 1.5s | **5s** (popover still kept) |
| Quickshell sidebar surface | translucent (α 0.78) | **opaque** |
| niri unfocused-window fade | 0.85 | **off** (opaque) |
| screensaver (tte) frame rate | 120 fps | **60 fps** |

Everything else — launcher, flyouts, sysmon detail popover, clocks, workspaces
— is identical. Windows still animate in light (spec wants motion everywhere);
they just don't run a sustained spring simulation.

**Mechanics — niri config is GENERATED, not symlinked.** niri's `layout {}` and
`animations {}` are **single nodes**; having them twice (or via `include`) is a
hard parse error (`duplicate node 'layout'`). So:

```
dotfiles/niri/config.base.kdl    # shared: inputs, outputs, binds, autostart, env
dotfiles/niri/config.full.kdl    # full:  layout{+shadow} + animations + opacity rules
dotfiles/niri/config.light.kdl   # light: layout{shadow off} + cheap anims + opaque
```

`rice-profile` concatenates `config.base.kdl` + `config.<profile>.kdl` →
`~/.config/niri/config.kdl`, **validates with `niri validate` before swapping it
in** (a broken fragment can never strand the session), then pokes
`niri msg action load-config-file`. The Quickshell half reacts off the
`Services.Profile` singleton (`services/Profile.qml`), which watches
`~/.config/rice/profile` and re-flows the bars with no restart.

> The theme's focus ring is the exception to "one layout block": both fragments
> end with `include optional=true "colors.kdl"`, which rice-theme writes. niri
> 26.04 merges an included `layout {}` field by field (a second `layout {}`
> *in the same file* is still a hard error).
>
> When editing niri config, **edit the fragments**, never the generated
> `config.kdl`. After editing, run `rice-profile <profile>` to regenerate.
> Keep shared `layout` fields (gaps/widths/struts/border) in sync across both
> fragments — niri can't merge a partial `layout` block.

The visual is in `arch rice v5 daily-driver.html`. The user has tuned
it. Match its hover/animation/translucency behavior beat-for-beat in
QML. Every transition, every hover state, every flyout — animated.

---

## 13. Theming — `rice-theme` (4-colour palettes)

Colour is driven by **four colours** (`c1` accent/hero, `c2` blue, `c3` cyan,
`c4` teal) plus an optional **`base`** — the near-black every bar, panel,
flyout, notification, terminal, lock and login background is built on (themes
without it keep the legacy `#0f1016`). All other shades are derived. Same generate-and-reload spirit as
`rice-profile`:

- **Quickshell** binds to `Theme.<token>` in `dotfiles/quickshell/Theme.qml`,
  which reads `~/.config/rice/colors` **live** (FileView) → re-themes with no
  restart. **Never hardcode a themed hex in QML** — add/use a `Theme` token.
  Dark fills use `Theme.tint(Theme.base | baseRaised | baseDeep, alpha)`.
- **btop / hyprlock / fastfetch / mako / zsh / alacritty's background** can't
  watch a file, so `rice-theme` **generates** them from
  `dotfiles/rice/templates/*` (btop and `~/.config/rice/alacritty-colors.toml`
  emitted inline) into `~/.config` on each switch. hyprlock wants
  `rgba(rrggbbaa)`, so its template uses `@ACCENT_RGBA@` / `@BASE_RGBA@`.
  mako's config is generated (not linked) and `makoctl reload`ed.
- `rice-theme list|status|set <name>|next|apply-colors c1..c4 [base]|save <name>|
  create <name> c1..c4 [base]`. **Mod+T** = Quickshell picker overlay;
  **Mod+Shift+T** = cycle. The default is **`deccan`** (Deccan Gate:
  `#f0522d #dfe5eb #39d98a #9fb4c7`, base `#111215`); the original `indigo`
  (`#5b6ee0 #60a5fa #22d3ee #2dd4bf`) still ships.
- **Logo:** the stock **Arch Linux** logo everywhere (user's call, 2026-10-28 —
  the संगणक chip mark is retired; the sanganak *name* stays). Bar: the Nerd
  Font glyph U+F303 in the accent (`bars/widgets/Logo.qml`). hyprlock: the same
  glyph as a `label`. fastfetch: the builtin `arch` logo, both colour slots =
  accent. ly, the ISO installer and Finish setup: the Arch ASCII art from
  `scripts/arch-logo.py` (→ `arch-logo`, stdlib Python) — a durdraw file
  `/etc/ly/archlinux.dur` written by `theme-ly.sh` (skipped on an ly without
  `dur_file_path`), or truecolor ANSI.
  ly and Limine are root-owned and resync on demand (`sudo scripts/theme-ly.sh`,
  `sudo scripts/theme-limine.sh`); both use `base` for their background.
- New palettes are **live-only until `save`d** (explicit). App-brand and
  semantic (`#f43f5e`) colours and alacritty's ANSI palette are **not** themed.
- **Wallpaper theme (pywal) — the default.** `rice-theme wal` (= `set wal`)
  runs `wal -n -s -t -e` on the current wallpaper (`~/.cache/wallpaper-current`,
  written by `wallpaper-init` / `wallpaper-next`) and maps pywal's six image
  colours onto the palette: c1 = the most vivid (saturation lifted to ≥ 0.38,
  value ≥ 0.78 so it reads on black), c2–c4 = the rest picked for the biggest
  difference, base = pywal's background hue at value 0.075. The active theme
  stays `wal`, so every wallpaper change re-themes the whole rice
  (`rice-theme wal-sync`, quiet). It leads the Mod+T picker and the Mod+Shift+T
  cycle; picking a named theme leaves wallpaper mode. Without pywal or a
  wallpaper it keeps rendering the live palette (else deccan) and waits.
- **Browser (Zen, the default):** `zen-theme apply` (scripts/zen-theme.py, run
  by every `rice-theme` switch and at niri startup) gives Zen's first workspace
  c1 and its second c2 (further ones alternate), as Zen picker dots in
  `<profile>/zen-sessions.jsonlz4`. Zen reads that only at startup and rewrites
  it while running, so with Zen open the change is queued (one waiter) and
  lands when Zen closes; the old file is kept as `.rice-bak`.
- **Login screen follows automatically:** `apply_palette` ends with
  `sudo -n /usr/local/bin/theme-ly`, allowed by `/etc/sudoers.d/30-theme-ly`
  (07-services.sh: `%wheel`, that exact path, **no arguments**). Limine stays
  manual (re-signing); rice-theme's drift reminder covers it.

Full colour map + procedure: **`docs/THEMING.md`** and the
**`.claude/skills/rice-theme`** skill. Edit rule: themed colour → a `Theme`
token (QML) or an `@TOKEN@` in a template (generated config), never a literal.

---

## 14. Omarchy-style tools, ISO, Finish setup

**Terminal tools** (`scripts/sanganak-*`, installed to `/usr/local/bin`; float
via niri rules on app-id `sanganak.float` / `sanganak.update`):
`sanganak-pkg-install` (repo, fzf + preview), `sanganak-pkg-aur-install`
(alt-b shows the PKGBUILD), `sanganak-pkg-remove`, `sanganak-update` (pending
list → keyring → `-Syu` → AUR → firmware metadata → orphans → .pacnew →
reboot on kernel change; log in `~/.local/state/sanganak/`),
`sanganak-keybindings`, `sanganak-agent-usage` (Claude / Codex usage records
for the agents panel), `sanganak-screensaver` (§6), `sanganak-dns` and
`sanganak-speedtest` (§Networking), `zen-theme` (§13), `wallpaper` (§4).

**ISO** (`iso/build.sh`, `sudo` from a normal user): archiso releng + an
offline repo holding the base system (all bootloader / laptop / USB
variants), `desktop.txt` and prebuilt `yay-bin`, with every dependency.
`sanganak-installer` (gum) starts on tty1 → `bootstrap.sh` with
`OFFLINE_CONF` → pacstrap from the repo → `iso-stage/06-rice-chroot.sh` sets
the rice up for the user with **no network** (modules run with
`SANGANAK_CHROOT=1`: no `--now`, no downloads). USB Secure Boot (shim + MOK)
stays on `scripts/build-usb.sh` from a running host.

**Finish setup** (`sanganak-finish-setup`): niri runs it with `--auto` at
every login; it exits at once once `~/.local/state/sanganak/setup-done`
exists. Otherwise it opens a floating terminal, gets online (Wi-Fi picker if
needed), upgrades, installs `apps.txt` + GPU extras + `aur.txt`, applies board
quirks that need the new packages. `install.sh` (in-place path) marks setup
done itself.

**Board quirks** (`modules/11-board-quirks.sh`, keyed on DMI board name):
B650 EAGLE AX → `acpi_enforce_resources=lax`, `spd5118` blacklist,
`rgb-apply` + boot/resume units, `pc-rgb` sudoers rule for the RGB overlay.

