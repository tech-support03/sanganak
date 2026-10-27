// ui/BarButton.qml — one icon slot in the edge bar. Left/middle/right clicks
// and the wheel are forwarded; `panelId` makes a left click toggle that panel
// next to this icon on this screen.
import QtQuick
import Quickshell
import "../theme"
import "../services" as Services

Item {
    id: b
    property string glyph: ""
    property string label: ""          // small text under the glyph (vertical bar)
    property color tint: Theme.fg0
    property real glyphSize: Theme.barIcon
    property string panelId: ""
    property bool highlighted: panelId !== "" && Services.Panels.openId === panelId
                               && Services.Panels.openScreen === screenName
    readonly property string screenName: QsWindow.window && QsWindow.window.screen ? QsWindow.window.screen.name : ""
    signal clicked(int button)
    signal wheel(int delta)

    implicitWidth: Theme.barSize
    implicitHeight: label !== "" ? Theme.barSlot + 12 : Theme.barSlot

    function togglePanel() {
        var p = b.mapToItem(null, 0, b.height / 2)
        Services.Panels.toggle(b.panelId, b.screenName, p.y)
    }

    Rectangle {
        anchors.centerIn: parent
        width: Theme.barSize - 16
        height: parent.height - 4
        radius: Theme.radiusSmall
        color: b.highlighted ? Theme.selectFill : (hov.hovered ? Qt.rgba(1, 1, 1, 0.09) : "transparent")
        Behavior on color { ColorAnimation { duration: Theme.animFast } }
    }
    Column {
        anchors.centerIn: parent
        scale: tap.pressed ? 0.88 : 1
        Behavior on scale { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutBack } }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: b.glyph
            color: b.tint
            font.family: Theme.fontMono
            font.pixelSize: b.glyphSize
            Behavior on color { ColorAnimation { duration: Theme.animFast } }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: b.label !== ""
            text: b.label
            color: Theme.fg1
            font.family: Theme.fontMono
            font.pixelSize: 9
        }
    }
    HoverHandler { id: hov; cursorShape: Qt.PointingHandCursor }
    TapHandler {
        id: tap
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
        onTapped: function (ev, button) {
            if (button === Qt.LeftButton && b.panelId !== "") b.togglePanel()
            b.clicked(button)
        }
    }
    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: function (ev) { b.wheel(ev.angleDelta.y) }
    }
}
