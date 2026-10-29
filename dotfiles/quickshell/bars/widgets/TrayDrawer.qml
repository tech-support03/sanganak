// The tray, tucked above the system monitor: every tray icon (Discord,
// wooting-bg-service, …) behind a small handle; hovering it slides the icons
// out, and they stay out while the pointer is on them or one of their menus is
// open. While an icon in here shows an unread dot (Discord), the handle carries
// an accent dot. Gone entirely when nothing has a tray icon.
import QtQuick
import "../../theme"

Item {
    id: d
    visible: services.count > 0
    width: Theme.barSize
    readonly property bool wantOpen: hover.hovered || services.openMenus > 0
    property bool open: false
    // Close a beat after the pointer leaves, so crossing a gap doesn't flicker.
    onWantOpenChanged: if (wantOpen) { closeTimer.stop(); open = true } else closeTimer.restart()
    Timer { id: closeTimer; interval: 250; onTriggered: d.open = false }

    implicitHeight: handle.height + (open ? services.implicitHeight + 4 : 0)
    Behavior on implicitHeight { NumberAnimation { duration: Theme.animMed; easing.type: Easing.OutCubic } }
    clip: true

    HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }

    Text {
        id: handle
        anchors.horizontalCenter: parent.horizontalCenter
        height: 18
        verticalAlignment: Text.AlignVCenter
        text: "󰇘"      // nf-md-dots_horizontal
        color: d.open ? Theme.fg1 : Theme.fg3
        font.family: Theme.fontMono
        font.pixelSize: 13
        Behavior on color { ColorAnimation { duration: Theme.animFast } }
    }
    Rectangle {
        // Unread somewhere inside.
        x: handle.x + handle.width - 1
        y: 3
        width: 6; height: 6; radius: 3
        color: Theme.accent
        opacity: services.badges > 0 && !d.open ? 1 : 0
        scale: opacity
        Behavior on opacity { NumberAnimation { duration: Theme.animMed; easing.type: Easing.OutBack } }
    }
    Tray {
        id: services
        mode: "services"
        y: handle.height + 4
        opacity: d.open ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.animFast } }
    }
}
