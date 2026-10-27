// Vertical 12-hour clock: h / — / mm / AM. Click opens the calendar.
import QtQuick
import Quickshell
import "../../theme"
import "../../ui"

BarButton {
    id: c
    panelId: "calendar"
    glyph: ""
    implicitHeight: col.implicitHeight + 12
    SystemClock { id: clock; precision: SystemClock.Minutes }
    Column {
        id: col
        anchors.centerIn: parent
        spacing: 0
        Repeater {
            // "h" is only 12-hour when AP is in the same format string.
            model: Qt.formatDateTime(clock.date, "h|—|mm|AP").split("|")
            Text {
                required property var modelData
                required property int index
                anchors.horizontalCenter: parent.horizontalCenter
                text: modelData
                color: index === 1 ? Theme.fg3 : (index === 3 ? Theme.fg1 : Theme.fg0)
                font.family: Theme.fontMono
                font.pixelSize: index === 3 ? 10 : (index === 1 ? 9 : 14)
                font.weight: index === 0 || index === 2 ? Font.DemiBold : Font.Normal
            }
        }
    }
}
