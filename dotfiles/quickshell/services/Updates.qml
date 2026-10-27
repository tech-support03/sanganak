// services/Updates.qml — pending package updates (official repos + AUR).
//
// `checkupdates` (pacman-contrib) syncs a private copy of the databases, so it
// never touches the real ones or needs root; `yay -Qua` covers the AUR. Checked
// at startup and hourly, and again after the update TUI exits.
pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: u

    // [{ name, from, to, aur }]
    property var packages: []
    property bool checking: false
    property string checkedAt: ""
    readonly property int total: packages.length
    readonly property int aurCount: packages.filter(function (p) { return p.aur }).length

    function check() { if (!_proc.running) { checking = true; _proc.running = true } }

    // Opens the update TUI in a floating terminal; rechecks when it closes.
    function runUpdate() {
        _run.command = ["alacritty", "--class", "sanganak.update", "-e", "sanganak-update"]
        _run.running = true
    }

    property Process _proc: Process {
        command: ["sh", "-c", "checkupdates 2>/dev/null | sed 's/^/repo /'; command -v yay >/dev/null && yay -Qua 2>/dev/null | sed 's/^/aur /'; true"]
        stdout: StdioCollector {
            onStreamFinished: {
                var out = []
                text.split("\n").forEach(function (ln) {
                    var m = ln.match(/^(repo|aur) (\S+) (\S+) -> (\S+)/)
                    if (m) out.push({ name: m[2], from: m[3], to: m[4], aur: m[1] === "aur" })
                })
                u.packages = out
                u.checking = false
                u.checkedAt = Qt.formatDateTime(new Date(), "h:mm AP")
            }
        }
    }
    property Process _run: Process { onExited: u.check() }

    property Timer _tick: Timer {
        interval: 60 * 60 * 1000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: u.check()
    }
}
