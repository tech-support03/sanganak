// Battery, laptops only: Services.Battery.present is the single gate, so the
// desktop never draws a battery indicator (CLAUDE.md §5.2).
import QtQuick
import "../../theme"
import "../../ui"
import "../../services" as Services

BarButton {
    panelId: "battery"
    visible: Services.Battery.present
    glyph: Services.Battery.glyph
    label: Services.Battery.percent + ""
    tint: Services.Battery.low ? Theme.danger : (Services.Battery.charging ? Theme.cyan : Theme.fg0)
}
