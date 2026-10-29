// services/Display.qml — monitors for the display panel and the bar's display
// icon: what each output is, its brightness, scale and on/off, and the UI text
// size.
//
//   outputs     `niri msg --json outputs` → name, model, mode, scale, enabled
//   brightness  an internal panel (eDP / LVDS / DSI) through brightnessctl;
//               external monitors through ddcutil (DDC/CI, VCP 0x10) on the
//               I2C bus `ddcutil detect` pairs with the DRM connector
//   scale, on/off  `niri msg output <name> scale|on|off` — live; nwg-displays
//               writes monitor.kdl to keep a layout across logins
//   text size   the GTK UI font size (gsettings org.gnome.desktop.interface
//               font-name), live in GTK apps
pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: d

    // [{ name, model, enabled, internal, width, height, refresh, scale, vrr }]
    property var outputs: []
    // name -> 0..100, for outputs whose brightness can be read and set
    property var level: ({})
    // DRM connector -> I2C bus number, from `ddcutil detect`
    property var _ddcBus: ({})
    property string fontFamily: "SF Pro Text"
    property int textSize: 11
    readonly property var textSizes: [9, 10, 11, 12, 14, 16, 20]
    readonly property var scales: [1, 1.25, 1.6, 2, 3, 4]

    function output(name) {
        for (var i = 0; i < outputs.length; i++) if (outputs[i].name === name) return outputs[i]
        return null
    }
    function hasBrightness(name) { return level[name] !== undefined }
    readonly property int enabledCount: outputs.filter(function (o) { return o.enabled }).length

    // Scales that give this mode a whole-pixel logical size (and stay usable).
    function validScales(o) {
        if (!o || !o.width) return [1]
        return scales.filter(function (s) {
            var w = o.width / s, h = o.height / s
            return Math.abs(w - Math.round(w)) < 1e-6 && Math.abs(h - Math.round(h)) < 1e-6 && w >= 640
        })
    }
    // The brightness "mood" shown under the panel title.
    function mood(pct) {
        if (pct >= 95) return "Sun blast"
        if (pct >= 80) return "Solar flare"
        if (pct >= 65) return "Golden hour"
        if (pct >= 45) return "Even day"
        if (pct >= 30) return "Soft glow"
        if (pct >= 20) return "Lamp light"
        if (pct >= 10) return "Candlelit"
        return "Night owl"
    }

    function refresh() { if (!_probe.running) _probe.running = true }

    // ---- outputs, backlight, font ----------------------------------------
    property Process _probe: Process {
        command: ["sh", "-c",
            "niri msg --json outputs; printf '\\036'; " +
            "brightnessctl -m -c backlight 2>/dev/null | head -1; printf '\\036'; " +
            "gsettings get org.gnome.desktop.interface font-name 2>/dev/null"]
        stdout: StdioCollector { onStreamFinished: d._ingest(text) }
    }
    function _ingest(text) {
        var parts = text.split("\x1e")
        var outs = [], lv = Object.assign({}, level)
        try {
            var j = JSON.parse(parts[0])
            for (var name in j) {
                var o = j[name], m = o.modes && o.current_mode !== null ? o.modes[o.current_mode] : null
                outs.push({ name: name, model: ((o.make || "") + " " + (o.model || "")).trim(),
                            enabled: !!o.logical, internal: /^(eDP|LVDS|DSI)/.test(name),
                            width: m ? m.width : 0, height: m ? m.height : 0,
                            refresh: m ? Math.round(m.refresh_rate / 1000) : 0,
                            scale: o.logical ? o.logical.scale : 1,
                            vrr: !!o.vrr_enabled })
            }
            outs.sort(function (a, b) { return a.name.localeCompare(b.name) })
        } catch (e) { return }
        // "intel_backlight,backlight,512,48%,1060" — the percentage is field 4.
        var bl = (parts[1] || "").trim().split(",")
        outs.forEach(function (o) { if (o.internal && bl.length > 3) lv[o.name] = parseInt(bl[3]) })
        var fm = (parts[2] || "").match(/'(.*?)\s+(\d+(?:\.\d+)?)'/)
        if (fm) { fontFamily = fm[1]; textSize = Math.round(parseFloat(fm[2])) }
        outputs = outs
        level = lv
        var missing = outs.some(function (o) { return !o.internal && o.enabled && d._ddcBus[o.name] === undefined })
        if (missing && !_detect.running) _detect.running = true
        else _readDdc()
    }

    // ---- DDC/CI: which bus drives which connector, then VCP 0x10 ----------
    property Process _detect: Process {
        command: ["sh", "-c", "command -v ddcutil >/dev/null && ddcutil detect --brief 2>/dev/null; true"]
        stdout: StdioCollector {
            onStreamFinished: {
                var map = {}, bus = ""
                text.split("\n").forEach(function (ln) {
                    var b = ln.match(/I2C bus:\s+\/dev\/i2c-(\d+)/)
                    if (b) bus = b[1]
                    var c = ln.match(/DRM connector:\s+card\d+-(\S+)/)
                    if (c && bus !== "") map[c[1]] = bus
                })
                // Remember outputs without DDC too, so they aren't re-probed.
                d.outputs.forEach(function (o) { if (!o.internal && map[o.name] === undefined) map[o.name] = "" })
                d._ddcBus = map
                d._readDdc()
            }
        }
    }
    function _readDdc() {
        var cmd = ""
        outputs.forEach(function (o) {
            var bus = _ddcBus[o.name]
            if (o.enabled && bus) cmd += "echo \"" + o.name + " $(ddcutil --bus " + bus + " -t getvcp 10 2>/dev/null)\"; "
        })
        if (cmd === "" || _ddcRead.running) return
        _ddcRead.command = ["sh", "-c", cmd]
        _ddcRead.running = true
    }
    property Process _ddcRead: Process {
        stdout: StdioCollector {
            onStreamFinished: {
                var lv = Object.assign({}, d.level)
                text.split("\n").forEach(function (ln) {
                    var m = ln.match(/^(\S+) VCP 10 C (\d+) (\d+)/)
                    if (m) lv[m[1]] = Math.round(100 * parseInt(m[2]) / Math.max(1, parseInt(m[3])))
                })
                d.level = lv
            }
        }
    }

    // ---- writes -------------------------------------------------------------
    // Brightness writes are coalesced per output and run one after another, so
    // a dragged slider never queues dozens of DDC transactions on one bus.
    property var _pending: ({})
    function setBrightness(name, pct) {
        pct = Math.max(1, Math.min(100, Math.round(pct)))
        var lv = Object.assign({}, level); lv[name] = pct; level = lv
        var p = Object.assign({}, _pending); p[name] = pct; _pending = p
        _flush.restart()
    }
    function step(name, delta) { if (hasBrightness(name)) setBrightness(name, level[name] + delta) }
    property Timer _flush: Timer {
        interval: 180
        onTriggered: {
            if (d._write.running) { restart(); return }
            var cmd = ""
            for (var name in d._pending) {
                var o = d.output(name), pct = d._pending[name]
                if (!o) continue
                if (o.internal) cmd += "brightnessctl -q set " + pct + "%; "
                else if (d._ddcBus[name]) cmd += "ddcutil --bus " + d._ddcBus[name] + " --noverify setvcp 10 " + pct + "; "
            }
            d._pending = ({})
            if (cmd === "") return
            d._write.command = ["sh", "-c", cmd]
            d._write.running = true
        }
    }
    property Process _write: Process { }

    function setScale(name, s) {
        Quickshell.execDetached(["niri", "msg", "output", name, "scale", String(s)])
        _reprobe.restart()
    }
    // Never switch off the last screen that's on.
    function canToggle(o) { return !o.enabled || enabledCount > 1 }
    function setEnabled(name, on) {
        var o = output(name)
        if (!o || (!on && !canToggle(o))) return
        Quickshell.execDetached(["niri", "msg", "output", name, on ? "on" : "off"])
        _reprobe.restart()
    }
    function setTextSize(px) {
        textSize = px
        Quickshell.execDetached(["sh", "-c",
            "gsettings set org.gnome.desktop.interface font-name \"$0 $1\" && " +
            "gsettings set org.gnome.desktop.interface document-font-name \"$0 $1\"", fontFamily, String(px)])
    }
    property Timer _reprobe: Timer { interval: 600; onTriggered: d.refresh() }

    Component.onCompleted: refresh()
}
