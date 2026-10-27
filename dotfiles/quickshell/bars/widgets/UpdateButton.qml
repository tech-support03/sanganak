// Shows only when updates are pending (official + AUR). Click opens the
// updates panel; middle click runs the update TUI straight away.
import QtQuick
import Quickshell
import "../../theme"
import "../../ui"
import "../../services" as Services

BarButton {
    panelId: "updates"
    visible: Services.Updates.total > 0
    glyph: ""
    tint: Theme.accentBright
    label: String(Services.Updates.total)
    onClicked: function (button) { if (button === Qt.MiddleButton) Services.Updates.runUpdate() }
}
