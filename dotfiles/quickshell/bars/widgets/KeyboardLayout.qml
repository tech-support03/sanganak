// Current keyboard layout, only when niri has more than one. Click cycles.
import QtQuick
import "../../theme"
import "../../ui"
import "../../services" as Services

BarButton {
    visible: Services.Niri.layoutNames.length > 1
    glyph: ""
    label: {
        var n = Services.Niri.currentLayout
        var m = n.match(/\(([^)]+)\)/)
        return (m ? m[1] : n).slice(0, 3).toUpperCase()
    }
    onClicked: Services.Niri.switchLayout("next")
}
