# Theming

The rice is themed by **four colours**. Pick them; everything else (shades,
gradients, the prompt tail) is derived. Quickshell re-themes **live**; the other
surfaces regenerate and reload on next launch.

```
c1 = accent / hero      c2 = blue      c3 = cyan      c4 = teal
```

## Quick start

```sh
rice-theme list                 # saved themes (● = active)
rice-theme set indigo           # apply a saved theme
rice-theme apply-colors '#5b6ee0' '#60a5fa' '#22d3ee' '#2dd4bf'   # apply live, unsaved
rice-theme save mytheme         # keep the current live palette as a named theme
rice-theme next                 # cycle to the next theme
rice-theme status               # active theme name
rice-theme set wal              # follow the wallpaper (pywal) — the default
```

## Wallpaper theme (pywal)

`wal` is a theme like any other, except its colours come from the wallpaper.
`rice-theme wal` (same as `set wal`) runs pywal (`python-pywal16`) on the
current wallpaper — `~/.cache/wallpaper-current`, kept by `wallpaper-init` and
`wallpaper-next` — with `-n -s -t -e` (it never sets the wallpaper, recolours
open terminals or reloads gtk/xrdb), then maps pywal's six image colours:

| Slot | From pywal |
|---|---|
| c1 accent | the most vivid colour; saturation lifted to ≥ 0.38 and value ≥ 0.78 so it reads on black |
| c2, c3, c4 | the rest, picked greedily for the biggest difference from those already chosen; value ≥ 0.66 |
| base | pywal's background hue at value 0.075 (the rice's near-black) |

While `wal` is active, every wallpaper change runs `rice-theme wal-sync`, so
the bars, panels, power menu, launcher, lock screen, mako, alacritty's
background, btop, fastfetch, the zsh prompt, niri's focus ring, the ly
greeter and Zen's two workspace colours (from its next start) all follow the
wallpaper. Picking a saved theme (Mod+T, Mod+Shift+T,
`set <name>`) leaves wallpaper mode; `wal` leads both the picker and the cycle.
The last wallpaper palette is kept in `~/.config/rice/wal.palette` for the
picker's swatch. Like any palette it can be kept: `rice-theme save <name>`.

Without pywal or a wallpaper yet (a fresh install before Finish setup), `wal`
stays selected and the configs render from the live palette (else deccan).

| Key | Action |
|---|---|
| **Mod+T** | open the Quickshell theme picker (swatch menu) |
| **Mod+Shift+T** | cycle to the next saved theme (+ notification) |

Themes live in `~/.config/rice/themes/*.theme` (4 colours each, plus an
optional `base=` — the near-black behind every bar, panel, notification,
terminal, lock and login screen). The default is **`deccan`** (Deccan Gate:
`#f0522d #dfe5eb #39d98a #9fb4c7`, base `#111215`); **`indigo`** is the palette
the rice originally shipped with. New palettes are **live-only
until you `save` them** (or click-create in the picker).

## How it works

`rice-theme` is the single entry point (`scripts/rice-theme.sh`). On a switch it:

1. Writes the 4 colours to **`~/.config/rice/colors`**. Quickshell's
   `Theme.qml` watches this file (a `FileView`, same pattern as the `Profile`
   singleton) and re-derives every token **live — no restart**.
2. Derives all shades and **generates** the configs that can't watch a file:
   - `~/.config/btop/themes/sanganak.theme` (emitted by the script)
   - `~/.config/hypr/hyprlock.conf` (from `dotfiles/rice/templates/hyprlock.conf.tmpl`)
   - `~/.config/fastfetch/config.jsonc` (from `…/fastfetch-config.jsonc.tmpl`)
   - `~/.config/rice/colors.sh` — shell vars the **zsh prompt** sources
   - `~/.config/niri/colors.kdl` — the gradient focus ring (accent → c2), which
     both niri profile fragments include; niri live-reloads it
   - `~/.config/mako/config` and alacritty's background (`alacritty-colors.toml`)
3. Colours **Zen**'s workspaces (`zen-theme apply`): workspace 1 = c1,
   workspace 2 = c2. Zen reads them only at startup, so with Zen open the
   change waits until it closes.
4. Re-themes the **ly** greeter: `sudo -n /usr/local/bin/theme-ly`, allowed by
   `/etc/sudoers.d/30-theme-ly` (no arguments only). The Limine boot menu needs
   a re-sign, so it stays manual (`sudo theme-limine`) and a reminder fires when
   it drifts.
5. Sends a `notify-send` toast (on cycle).

btop/hyprlock/fastfetch pick up the change on next launch; the zsh prompt on the
next new terminal.

### Derived tokens

From `c1` (accent): `accentBright` (lighter — big clock, gradient peaks),
`accentDim` (darker — borders, gradient starts), `accentMuted`, `surfaceTint`
(very dark — album-art placeholder). From `c2`: `blueBright`. `c3`/`c4` are used
directly. Derivation lives in two mirrored places: `Theme.qml` (QML
`Qt.lighter/darker`) for Quickshell, and the Python block in `rice-theme.sh`
for everything else.

## Colour map — what each slot drives

| Surface | c1 accent | c2 blue | c3 cyan | c4 teal |
|---|---|---|---|---|
| niri | focus ring gradient start | focus ring gradient end | — | — |
| Quickshell sidebar | logo, focused-window pill, alacritty dock tint | network · bluetooth · sound widgets | — | — |
| Quickshell top bar | clock (bright), media waveform, art tint/note | media title (bright) | weather | — |
| Quickshell sysmon (+ flyout) | CPU | MEM | GPU | Disk |
| Quickshell calendar | "today", ‹ › arrows | — | — | — |
| Quickshell launcher / power flyout | selection, icon tiles, card edge | — | — | — |
| Quickshell tray | Discord's unread dot (repainted) | — | — | — |
| screensaver (tte) | final gradient start | final gradient end | — | — |
| btop | CPU, temp, download, hi/selected/boxes | MEM box, "used" ramp, cached | "available", temp peak | NET box, free, upload |
| hyprlock | Arch logo, clock (bright), input outline + `check_color` | — | — | — |
| fastfetch | title + Arch logo | — | keys | — |
| ly greeter | box border, Arch logo | — | — | — |
| Zen browser | workspace 1 colour | workspace 2 colour | — | — |
| zsh prompt | user\|host block + dim 2nd block | tail | tail | tail end |

**Not themed (intentionally):** app-brand dock tints (spotify/discord/steam/
whatsapp), battery/danger red `#f43f5e`, and alacritty's 16-colour ANSI palette.

## What changed (June 2026)

This theming system replaced a scheme where **every colour was hardcoded** and
the `Theme.qml` singleton was unused. The work, in order:

1. **zsh autocomplete shell** — zsh + `zsh-autosuggestions` /
   `-syntax-highlighting` / `-completions`, a Powerline prompt, ported bash bits
   (`PATH`, fastfetch greeting, `new` alias). See `dotfiles/zsh/.zshrc`,
   `01-base-packages.sh`, `install.sh` (`chsh`).
2. **Indigo recolour** — retired the lavender accent `#c5b3ff` for indigo
   `#5b6ee0` + blue/cyan/teal across the whole rice.
3. **Theme engine** — `Theme.qml` now reads the 4 colours live and derives the
   rest; **all** hardcoded accent hexes in the Quickshell QML were refactored to
   `Theme.<token>`; `rice-theme` + templates + the `Mod+T` picker + `Mod+Shift+T`
   cycle were added.

> **Editing rule:** never hardcode a themed colour. In QML use a `Theme` token;
> in a generated config use an `@TOKEN@` in its template + emit it in
> `rice-theme.sh`. App-brand and semantic colours are the only literal hexes.
> Full procedure for applying/adding themes: `.claude/skills/rice-theme/SKILL.md`.
