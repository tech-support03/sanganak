// niri workspaces on this output, top to bottom in niri's order. The focused
// one is an accent pill; occupied ones are full strength; empty ones dim.
// niri keeps one empty workspace below the last occupied one — it is shown
// too, so there is always somewhere new to go.
import QtQuick
import "../../theme"
import "../../services" as Services

Column {
    id: ws
    required property string screenName
    readonly property var list: Services.Niri.workspacesOn(screenName)
    spacing: 2
    width: Theme.barSize

    Repeater {
        model: ws.list
        delegate: Item {
            required property var modelData
            readonly property bool focused: modelData.is_active
            readonly property bool occupied: modelData.active_window_id !== null && modelData.active_window_id !== undefined
            width: Theme.barSize
            height: 26

            Rectangle {
                anchors.centerIn: parent
                width: parent.focused ? 6 : (hov.hovered ? 8 : 6)
                height: parent.focused ? 20 : width
                radius: width / 2
                color: parent.focused ? Theme.accent : Theme.fg0
                opacity: parent.focused ? 1 : (parent.occupied ? 0.85 : 0.3)
                Behavior on height { NumberAnimation { duration: Theme.animMed; easing.type: Easing.OutBack } }
                Behavior on width { NumberAnimation { duration: Theme.animFast } }
                Behavior on color { ColorAnimation { duration: Theme.animMed } }
                Behavior on opacity { NumberAnimation { duration: Theme.animFast } }
            }
            HoverHandler { id: hov; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: Services.Niri.focusWorkspaceOn(ws.screenName, modelData.idx) }
        }
    }
    WheelHandler {
        onWheel: function (ev) { Services.Niri.act([ev.angleDelta.y > 0 ? "focus-workspace-up" : "focus-workspace-down"]) }
    }
}
