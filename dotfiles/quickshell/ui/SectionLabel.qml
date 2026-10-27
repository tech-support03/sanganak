// ui/SectionLabel.qml — small caps heading with an optional right-hand value.
import QtQuick
import "../theme"

Item {
    property string text: ""
    property string value: ""
    width: parent ? parent.width : 0
    implicitHeight: 14
    Text {
        text: parent.text.toUpperCase()
        color: Theme.fg2
        font.family: Theme.fontSans
        font.pixelSize: 9
        font.weight: Font.Medium
        font.letterSpacing: 1.4
    }
    Text {
        anchors.right: parent.right
        text: parent.value
        color: Theme.fg2
        font.family: Theme.fontMono
        font.pixelSize: 10
    }
}
