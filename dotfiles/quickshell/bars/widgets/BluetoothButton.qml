// Bluetooth: panel on left click, radio toggle on right click. The solid
// Font Awesome mark matches the bar's other filled icons (the Material one is a
// thin outline); off just dims it, like network and audio do.
import QtQuick
import "../../theme"
import "../../ui"
import "../../services" as Services

BarButton {
    panelId: "bluetooth"
    visible: Services.Bluetooth.available
    glyph: "\uF293"      // nf-fa-bluetooth
    tint: Services.Bluetooth.powered ? Theme.fg0 : Theme.fg3
    onClicked: function (button) { if (button === Qt.RightButton) Services.Bluetooth.togglePower() }
}
