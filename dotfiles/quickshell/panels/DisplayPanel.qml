// Display: brightness per screen and niri output scale.
//
// Laptop panels go through brightnessctl (backlight class); external monitors
// through ddcutil (DDC/CI) when it is installed. `niri msg --json outputs`
// lists the outputs and their scale; scale buttons apply live with
// `niri msg output <name> scale <x>` (not persisted — edit the niri config or
// use nwg-displays to keep it).
import QtQuick
import Quickshell
import Quickshell.Io
import "../theme"
import "../ui"
import "../services" as Services

Panel {
    id: p
    panelId: "display"
    title: "Display"
    glyph: "󰃟"
    subtitle: outputs.length + (outputs.length === 1 ? " screen" : " screens")

    // [{ name, model, scale, backlight (bool), bus (ddc bus or ""), level 0..1 }]
    property var outputs: []
    onOpenChanged: if (open) probe.running = true

    Process {
        id: probe
        command: ["sh", "-c",
            "niri msg --json outputs; echo '\\x1e'; " +
            "for b in /sys/class/backlight/*; do [ -e \"$b\" ] && echo \"bl $(cat $b/brightness) $(cat $b/max_brightness)\"; done; echo '\\x1e'; " +
            "command -v ddcutil >/dev/null && ddcutil detect --brief 2>/dev/null | awk '/I2C bus/{bus=$3} /DRM connector/{print bus, $3}'; true"]
        stdout: StdioCollector {
            onStreamFinished: {
                var parts = text.split("\x1e")
                var outs = []
                try {
                    var j = JSON.parse(parts[0])
                    var bl = (parts[1] || "").match(/bl (\d+) (\d+)/)
                    var ddc = {}
                    ;(parts[2] || "").split("\n").forEach(function (ln) {
                        var m = ln.trim().match(/\/dev\/i2c-(\d+)\s+card\d+-(.+)/)
                        if (m) ddc[m[2]] = m[1]
                    })
                    for (var name in j) {
                        var o = j[name]
                        var internal = /^(eDP|LVDS|DSI)/.test(name)
                        outs.push({ name: name, model: (o.make + " " + o.model).trim(),
                                    scale: o.logical ? o.logical.scale : 1,
                                    backlight: internal && !!bl, bus: ddc[name] || "",
                                    level: internal && bl ? parseInt(bl[1]) / parseInt(bl[2]) : -1 })
                    }
                } catch (e) { }
                p.outputs = outs
                outs.forEach(function (o, i) { if (o.bus !== "") p.readDdc(i) })
            }
        }
    }
    function readDdc(i) {
        var o = outputs[i]
        var proc = ddcRead.createObject(p, { index: i, command: ["ddcutil", "--bus", o.bus, "-t", "getvcp", "10"] })
        proc.running = true
    }
    Component {
        id: ddcRead
        Process {
            id: rp
            property int index
            stdout: StdioCollector {
                onStreamFinished: {
                    var m = text.match(/VCP 10 C (\d+) (\d+)/)
                    if (!m) return
                    var list = p.outputs.slice()
                    var o = Object.assign({}, list[rp.index]); o.level = parseInt(m[1]) / parseInt(m[2]); list[rp.index] = o
                    p.outputs = list
                }
            }
            onExited: destroy()
        }
    }
    Timer { id: applyTimer; interval: 180; property var job: null
        onTriggered: if (job) Quickshell.execDetached(job) }
    function setLevel(o, v) {
        var pct = Math.max(1, Math.round(v * 100))
        applyTimer.job = o.backlight ? ["brightnessctl", "-q", "set", pct + "%"]
                                     : ["ddcutil", "--bus", o.bus, "--noverify", "setvcp", "10", String(pct)]
        applyTimer.restart()
    }

    Repeater {
        model: p.outputs
        Column {
            required property var modelData
            required property int index
            width: parent.width
            spacing: 6
            SectionLabel { text: modelData.name + "  " + modelData.model; value: modelData.level >= 0 ? Math.round(modelData.level * 100) + "%" : "" }
            Slider {
                width: parent.width
                visible: modelData.level >= 0
                value: modelData.level
                onMoved: function (v) {
                    var list = p.outputs.slice(); var o = Object.assign({}, list[index]); o.level = v; list[index] = o; p.outputs = list
                    p.setLevel(modelData, v)
                }
            }
            Text {
                visible: modelData.level < 0
                text: modelData.backlight || modelData.bus ? "Reading brightness…" : "No brightness control (install ddcutil for external monitors)"
                color: Theme.fg3
                font.family: Theme.fontSans
                font.pixelSize: 10
            }
            Row {
                spacing: 4
                Repeater {
                    model: [1, 1.25, 1.5, 2]
                    Rectangle {
                        required property var modelData
                        readonly property bool on: Math.abs(parent.parent.modelData.scale - modelData) < 0.01
                        width: 54; height: 24; radius: 12
                        color: on ? Theme.selectFill : (h.hovered ? Theme.hoverFill : Qt.rgba(1, 1, 1, 0.04))
                        Behavior on color { ColorAnimation { duration: Theme.animFast } }
                        Text { anchors.centerIn: parent; text: modelData + "×"; color: Theme.fg0; font.family: Theme.fontMono; font.pixelSize: 10 }
                        HoverHandler { id: h; cursorShape: Qt.PointingHandCursor }
                        TapHandler {
                            onTapped: {
                                Quickshell.execDetached(["niri", "msg", "output", parent.parent.parent.modelData.name, "scale", String(modelData)])
                                probeAgain.restart()
                            }
                        }
                    }
                }
            }
        }
    }
    Timer { id: probeAgain; interval: 400; onTriggered: probe.running = true }
    ListRow {
        glyph: "󰍹"
        label: "Arrange displays (nwg-displays)"
        onClicked: { Quickshell.execDetached(["nwg-displays"]); Services.Panels.close() }
    }
}
