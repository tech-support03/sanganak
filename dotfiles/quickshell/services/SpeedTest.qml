// services/SpeedTest.qml — the network panel's built-in speed test.
//
// Runs `sanganak-speedtest down`, then `up` (scripts/sanganak-speedtest.sh:
// curl against speed.cloudflare.com, or a mirror when Cloudflare rate-limits a
// download). Each phase names its server ("src …"), streams the live rate in
// Mbps a line at a time and ends with "avg <Mbps>", which becomes the result. It
// lives here rather than in the panel, so closing the panel doesn't stop a run
// and the last result is still there next time.
pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: st

    property string phase: "idle"      // idle | down | up | done | error
    property real down: 0               // Mbps — live while measuring, then the average
    property real up: 0
    property string downFrom: ""        // the server each direction measured against
    property string upFrom: ""
    property string error: ""
    readonly property bool running: phase === "down" || phase === "up"

    function run() {
        if (running) return
        down = 0; up = 0; error = ""; downFrom = ""; upFrom = ""
        _start("down")
    }
    function stop() {
        if (!running) return
        _proc.signal(15)
        phase = down > 0 ? "done" : "idle"
    }
    function _start(dir) {
        phase = dir
        _proc.command = ["sanganak-speedtest", dir]
        _proc.running = true
        _watchdog.restart()
    }

    property Process _proc: Process {
        stdout: SplitParser {
            onRead: function (line) {
                var src = line.match(/^src (.+)$/)
                if (src) { if (st.phase === "down") st.downFrom = src[1]; else st.upFrom = src[1]; return }
                var m = line.match(/^(avg )?(\d+)$/)
                if (!m) return
                var v = parseInt(m[2])
                if (st.phase === "down") st.down = v
                else if (st.phase === "up") st.up = v
            }
        }
        stderr: StdioCollector { id: errOut }
        onExited: function (code) {
            st._watchdog.stop()
            if (!st.running) return            // stopped by hand
            if (code !== 0) { st.error = errOut.text.trim() || "speed test failed"; st.phase = "error"; return }
            if (st.phase === "down") st._start("up")
            else st.phase = "done"
        }
    }
    // A phase takes ~8 s; anything past 20 s is stuck.
    property Timer _watchdog: Timer {
        interval: 20000
        onTriggered: { st._proc.signal(15); st.error = "timed out"; st.phase = "error" }
    }
}
