// Bluetooth: panel on left click, radio toggle on right click.
import QtQuick
import "../../theme"
import "../../ui"
import "../../services" as Services

BarButton {
    panelId: "bluetooth"
    visible: Services.Bluetooth.available
    glyph: Services.Bluetooth.glyph
    tint: Services.Bluetooth.powered ? Theme.fg0 : Theme.fg3
    onClicked: function (button) { if (button === Qt.RightButton) Services.Bluetooth.togglePower() }
}
