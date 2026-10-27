// Weather glyph + temperature. Click opens the forecast panel.
import QtQuick
import "../../theme"
import "../../ui"
import "../../services" as Services

BarButton {
    panelId: "weather"
    visible: Services.Weather.ready
    glyph: Services.Weather.glyph
    label: Services.Weather.tempF + "°"
}
