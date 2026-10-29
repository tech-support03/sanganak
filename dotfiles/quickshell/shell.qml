// ~/.config/quickshell/shell.qml — entry point
// Wires up the two bars — the right-edge bezel bar (EdgeBar, which also owns
// its panels) and the top media notch (TopBar) — plus the overlays. Each
// component lives in its own file; this just instantiates them.
//
// The lock screen is NOT handled by Quickshell — it's hyprlock, fired
// only by the Mod+L keybind in niri. Quickshell's WlSessionLock proved
// unstable; hyprlock owns locking (parallel fingerprint + password, per
// CLAUDE.md §6). No idle daemon — lock is manual-only; the only idle
// behaviour is the screensaver (overlays/Screensaver.qml).
//
// IMPORTANT: keep this file thin. Logic goes in services/, UI goes in
// bars/. Theme tokens come from Theme.qml — never hardcode a color here.

import QtQuick
import Quickshell
import "bars" as Bars
import "overlays" as Overlays

ShellRoot {
    id: root

    // --- panels (one per output handled inside each component) ---
    Bars.TopBar { }
    Bars.EdgeBar { }

    // --- overlays --------------------------------------------------------
    // Launchpad-style app grid. Triggered via `qs ipc call launcher toggle`
    // (wired to Mod+Space in niri).
    Overlays.Launcher { }

    // Power menu (lock / sign out / suspend / reboot / power off). Triggered
    // via `qs ipc call power toggle` (wired to Mod+Escape in niri).
    Overlays.PowerFlyout { }

    // Edge-bar panels (audio, network, bluetooth, calendar, weather, display,
    // battery, agents, sysmon, updates, menu) open from their bar icons or
    // `qs ipc call panel toggle <id>`; see services/Panels.qml.

    // Volume OSD. Pops up on any volume change; the niri XF86Audio* binds
    // fire `qs ipc call audio show` right after nudging wpctl.
    Overlays.VolumeOSD { }

    // Theme picker "menu". Triggered via `qs ipc call theme toggle` (wired to
    // Mod+T in niri); Mod+Shift+T cycles directly via `rice-theme next`.
    Overlays.ThemePicker { }

    // PC RGB control (fans + RAM colour/mode). Triggered via
    // `qs ipc call rgb toggle` (wired to Mod+Shift+R in niri). Drives pc-rgb.
    Overlays.RgbControl { }

    // Screensaver trigger: 2.5 min idle (Quickshell's IdleMonitor) starts
    // sanganak-screensaver, the next input ends it. Never locks.
    Overlays.Screensaver { }
}
