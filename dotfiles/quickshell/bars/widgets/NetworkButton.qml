// Network: Wi-Fi signal or wired glyph. Click opens the network panel.
import QtQuick
import "../../theme"
import "../../ui"
import "../../services" as Services

BarButton {
    panelId: "network"
    glyph: Services.Network.glyph
    tint: Services.Network.connected ? Theme.fg0 : Theme.fg3
}
