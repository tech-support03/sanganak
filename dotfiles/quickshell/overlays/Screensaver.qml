// ~/.config/quickshell/overlays/Screensaver.qml — idle trigger for the
// Omarchy-style screensaver (scripts/sanganak-screensaver.sh).
//
// Quickshell's own IdleMonitor (ext-idle-notify-v1), so there is still no idle
// daemon. After 2.5 minutes without input it starts the screensaver; the first
// input after that ends it. Idle inhibitors (a playing video, a game that asks)
// hold it off. It never locks and never blanks the screen — lock stays Mod+L
// only (CLAUDE.md §6). The sanganak menu can also start it on demand.

import QtQuick
import Quickshell
import Quickshell.Wayland

Scope {
    IdleMonitor {
        timeout: 150
        respectInhibitors: true
        onIsIdleChanged: Quickshell.execDetached(isIdle ? ["sanganak-screensaver"]
                                                        : ["sanganak-screensaver", "--stop"])
    }
}
