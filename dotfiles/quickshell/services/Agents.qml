// services/Agents.qml — AI coding agent usage records.
//
// `sanganak-agent-usage` writes one JSON record per agent (claude, codex) to
// ~/.local/state/sanganak/agents/; this watches that directory and reloads the
// records. It runs the collector at startup, every 5 minutes, and on refresh().
pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: a

    readonly property string dir: Quickshell.env("HOME") + "/.local/state/sanganak/agents"
    // [record, …] in a stable order (claude first).
    property var agents: []
    property bool refreshing: false
    // Highest limit use across all agents, 0..1 — the bar turns red near 1.
    readonly property real hottest: {
        var m = 0
        agents.forEach(function (r) { (r.limits || []).forEach(function (l) { m = Math.max(m, l.percent || 0) }) })
        return m
    }

    function refresh() { if (!_collect.running) { refreshing = true; _collect.running = true } }

    property Process _collect: Process {
        command: ["sanganak-agent-usage"]
        onExited: { a.refreshing = false; a._read.running = true }
    }
    property Process _read: Process {
        command: ["sh", "-c", 'for f in "$0"/*.json; do [ -f "$f" ] && { cat "$f"; echo; echo "\x1e"; }; done; true', a.dir]
        stdout: StdioCollector {
            onStreamFinished: {
                var out = []
                text.split("\x1e").forEach(function (chunk) {
                    chunk = chunk.trim()
                    if (!chunk) return
                    try { var r = JSON.parse(chunk); if (r.ready !== false) out.push(r) } catch (e) { }
                })
                var order = { claude: 0, codex: 1 }
                out.sort(function (x, y) { return (order[x.id] ?? 9) - (order[y.id] ?? 9) })
                a.agents = out
            }
        }
    }
    property Timer _tick: Timer {
        interval: 5 * 60 * 1000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: a.refresh()
    }
}
