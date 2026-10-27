// ui/Toggle.qml — pill switch. Click flips it and emits toggled(); the owner
// decides the real state (bind `checked` to the service, not to this item).
import QtQuick
import "../theme"

Rectangle {
    id: sw
    property bool checked: false
    signal toggled()

    implicitWidth: 40
    implicitHeight: 22
    radius: height / 2
    color: checked ? Theme.accent : Qt.rgba(1, 1, 1, hover.hovered ? 0.18 : 0.12)
    Behavior on color { ColorAnimation { duration: Theme.animFast } }

    Rectangle {
        width: parent.height - 6
        height: width
        radius: width / 2
        y: 3
        x: sw.checked ? sw.width - width - 3 : 3
        color: Theme.fg0
        Behavior on x { NumberAnimation { duration: Theme.animMed; easing.type: Easing.OutCubic } }
    }
    HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
    TapHandler { onTapped: sw.toggled() }
}
