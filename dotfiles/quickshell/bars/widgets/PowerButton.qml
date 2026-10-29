// Power menu (the rice's PowerFlyout overlay).
import QtQuick
import Quickshell
import "../../theme"
import "../../ui"

BarButton {
    glyph: ""
    onClicked: Quickshell.execDetached(["qs", "ipc", "call", "power", "toggle"])
}
