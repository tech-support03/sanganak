// Chip logo. Left click: fastfetch popup (system info). Right click: menu.
import QtQuick
import Quickshell
import "../../theme"
import "../../ui"
import "../../services" as Services

BarButton {
    id: b
    glyph: ""
    implicitHeight: Theme.barSlot + 8
    ChipLogo { anchors.centerIn: parent; size: 26 }
    onClicked: function (button) {
        if (button === Qt.RightButton) {
            var p = b.mapToItem(null, 0, b.height / 2)
            Services.Panels.toggle("menu", b.screenName, p.y)
        } else Quickshell.execDetached(["fastfetch-popup"])
    }
}
