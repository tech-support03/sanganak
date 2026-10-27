// Battery (laptops): charge, time left, and the power profile when
// power-profiles-daemon is running.
import QtQuick
import Quickshell
import Quickshell.Io
import "../theme"
import "../ui"
import "../services" as Services

Panel {
    id: p
    panelId: "battery"
    readonly property var b: Services.Battery
    title: b.percent + "%"
    subtitle: b.status + (b.timeRemaining ? " · " + b.timeRemaining : "")
    glyph: b.glyph

    property string profile: ""
    property var profiles: []
    onOpenChanged: if (open) probe.running = true
    Process {
        id: probe
        command: ["sh", "-c", "command -v powerprofilesctl >/dev/null && powerprofilesctl get && powerprofilesctl list | sed -n 's/^[ *]*\\([a-z-]*\\):$/\\1/p'"]
        stdout: StdioCollector {
            onStreamFinished: {
                var l = text.trim().split("\n").filter(function (s) { return s.length > 0 })
                p.profile = l.length ? l[0] : ""
                p.profiles = l.slice(1)
            }
        }
    }

    Rectangle {
        width: parent.width; height: 10; radius: 5
        color: Qt.rgba(1, 1, 1, 0.08)
        Rectangle {
            width: parent.width * p.b.percent / 100; height: parent.height; radius: 5
            color: p.b.low ? Theme.danger : p.b.charging ? Theme.cyan : Theme.accent
            Behavior on width { NumberAnimation { duration: Theme.animMed } }
        }
    }
    SectionLabel { text: "Power profile"; visible: p.profiles.length > 0 }
    Repeater {
        model: p.profiles
        ListRow {
            required property var modelData
            glyph: modelData === "performance" ? "󰓅" : modelData === "power-saver" ? "󰌪" : "󰾅"
            label: modelData.charAt(0).toUpperCase() + modelData.slice(1).replace("-", " ")
            active: modelData === p.profile
            onClicked: { Quickshell.execDetached(["powerprofilesctl", "set", modelData]); p.profile = modelData }
        }
    }
}
