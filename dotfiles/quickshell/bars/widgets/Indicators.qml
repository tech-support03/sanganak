// State indicators that only appear while something is on: do-not-disturb
// (mako mode) and an active screen recording (wf-recorder / gpu-screen-recorder).
// Clicking an indicator turns that state off.
import QtQuick
import Quickshell
import Quickshell.Io
import "../../theme"
import "../../ui"

Column {
    id: ind
    property bool dnd: false
    property bool recording: false

    Process {
        id: probe
        command: ["sh", "-c", "makoctl mode 2>/dev/null | grep -qx do-not-disturb && echo dnd; pgrep -x 'wf-recorder|gpu-screen-recorder' >/dev/null && echo rec; true"]
        stdout: StdioCollector {
            onStreamFinished: { ind.dnd = text.indexOf("dnd") !== -1; ind.recording = text.indexOf("rec") !== -1 }
        }
    }
    Timer { interval: 2000; repeat: true; running: true; triggeredOnStart: true; onTriggered: probe.running = true }

    BarButton {
        visible: ind.dnd
        glyph: ""
        tint: Theme.accentBright
        onClicked: { Quickshell.execDetached(["makoctl", "mode", "-r", "do-not-disturb"]); ind.dnd = false }
    }
    BarButton {
        visible: ind.recording
        glyph: ""
        tint: Theme.danger
        onClicked: Quickshell.execDetached(["pkill", "-INT", "-x", "wf-recorder|gpu-screen-recorder"])
    }
}
