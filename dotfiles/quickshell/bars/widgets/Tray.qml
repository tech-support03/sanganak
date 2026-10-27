// StatusNotifier tray. Left click activates, right click opens the app's menu.
import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import "../../theme"

Column {
    id: tray
    spacing: 2
    Repeater {
        model: SystemTray.items
        delegate: Item {
            id: slot
            required property var modelData
            width: Theme.barSize
            height: 28
            Rectangle {
                anchors.centerIn: parent
                width: 30; height: 26; radius: Theme.radiusSmall
                color: hov.hovered ? Qt.rgba(1, 1, 1, 0.09) : "transparent"
                Behavior on color { ColorAnimation { duration: Theme.animFast } }
            }
            IconImage {
                anchors.centerIn: parent
                implicitSize: 16
                source: slot.modelData.icon
                scale: tap.pressed ? 0.85 : 1
                Behavior on scale { NumberAnimation { duration: Theme.animFast } }
            }
            QsMenuAnchor {
                id: menu
                menu: slot.modelData.menu
                anchor.item: slot
                anchor.edges: Edges.Left
                anchor.gravity: Edges.Left
            }
            HoverHandler { id: hov; cursorShape: Qt.PointingHandCursor }
            TapHandler {
                id: tap
                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                onTapped: function (ev, button) {
                    if (button === Qt.RightButton || slot.modelData.onlyMenu) { if (slot.modelData.hasMenu) menu.open() }
                    else if (button === Qt.MiddleButton) slot.modelData.secondaryActivate()
                    else slot.modelData.activate()
                }
            }
        }
    }
}
