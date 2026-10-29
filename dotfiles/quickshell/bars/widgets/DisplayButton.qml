// Display icon: one monitor or several. Click: the display panel. Wheel:
// this screen's brightness ±5% (brightnessctl / DDC/CI, services/Display.qml).
import QtQuick
import Quickshell
import "../../ui"
import "../../services" as Services

BarButton {
    id: b
    panelId: "display"
    glyph: Quickshell.screens.length > 1 ? "󰍺" : "󰍹"   // nf-md-monitor(_multiple)
    onWheel: function (delta) {
        if (!Services.Display.hasBrightness(b.screenName)) Services.Display.refresh()
        Services.Display.step(b.screenName, delta > 0 ? 5 : -5)
    }
}
