// Four mini meters (CPU, memory, GPU, disk). Click opens the detail panel;
// right click opens btop.
import QtQuick
import Quickshell
import "../../theme"
import "../../ui"
import "../../services" as Services

BarButton {
    id: m
    panelId: "sysmon"
    glyph: ""
    implicitHeight: col.implicitHeight + 12
    readonly property var rows: [
        { g: "󰍛", v: Services.SysStats.cpuPct },
        { g: "󰘚", v: Services.SysStats.memPct },
        { g: "󰢮", v: Services.SysStats.gpuPct },
        { g: "󰋊", v: Services.SysStats.diskPct }
    ]
    onClicked: function (button) { if (button === Qt.RightButton) Quickshell.execDetached(["alacritty", "--class", "sanganak.btop", "-e", "btop"]) }
    Column {
        id: col
        anchors.centerIn: parent
        spacing: 5
        Repeater {
            model: m.rows
            Column {
                required property var modelData
                spacing: 2
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: modelData.g + " " + modelData.v
                    color: Theme.fg0
                    font.family: Theme.fontMono
                    font.pixelSize: 10
                }
                Rectangle {
                    width: 26; height: 2; radius: 1
                    color: Qt.rgba(1, 1, 1, 0.14)
                    Rectangle {
                        width: parent.width * Math.min(1, modelData.v / 100)
                        height: 2; radius: 1
                        color: modelData.v >= 90 ? Theme.danger : Theme.fg0
                        Behavior on width { NumberAnimation { duration: Theme.animMed } }
                    }
                }
            }
        }
    }
}
