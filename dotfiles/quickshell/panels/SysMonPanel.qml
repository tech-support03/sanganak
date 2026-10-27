// System monitor detail: CPU, memory, GPU, disk with the facts SysStats has.
import QtQuick
import Quickshell
import "../theme"
import "../ui"
import "../services" as Services

Panel {
    id: p
    panelId: "sysmon"
    title: "System"
    glyph: "󰍛"
    readonly property var s: Services.SysStats
    readonly property var rows: [
        { t: "CPU", sub: s.cpuModel, v: s.cpuPct, c: Theme.accent, f: [s.cpuFreq, s.cpuTemp, s.cpuThreads] },
        { t: "Memory", sub: s.memTotal, v: s.memPct, c: Theme.blue, f: [s.memUsed, s.memRate] },
        { t: "GPU", sub: s.gpuModel, v: s.gpuPct, c: Theme.cyan, f: [s.gpuFreq, s.gpuTemp, s.gpuVram] },
        { t: "Disk", sub: s.diskMount, v: s.diskPct, c: Theme.teal, f: [s.diskUsed, s.diskFs, s.diskKind] }
    ]
    Repeater {
        model: p.rows
        Column {
            required property var modelData
            width: parent.width
            spacing: 5
            SectionLabel { text: modelData.t + (modelData.sub ? " · " + modelData.sub : ""); value: modelData.v + "%" }
            Rectangle {
                width: parent.width; height: 6; radius: 3
                color: Qt.rgba(1, 1, 1, 0.08)
                Rectangle {
                    width: parent.width * Math.min(1, modelData.v / 100); height: 6; radius: 3
                    color: modelData.v >= 90 ? Theme.danger : modelData.c
                    Behavior on width { NumberAnimation { duration: Theme.animMed } }
                }
            }
            Text {
                text: modelData.f.filter(function (x) { return x && String(x).length }).join("   ")
                color: Theme.fg1
                font.family: Theme.fontMono
                font.pixelSize: 10
            }
        }
    }
    ListRow {
        glyph: "󰄨"
        label: "Open btop"
        onClicked: { Quickshell.execDetached(["alacritty", "--class", "sanganak.btop", "-e", "btop"]); Services.Panels.close() }
    }
}
