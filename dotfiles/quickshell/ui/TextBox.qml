// ui/TextBox.qml — single-line input on the black panels. Enter emits
// accepted(text); Escape bubbles up so the panel closes.
import QtQuick
import "../theme"

Rectangle {
    id: box
    property alias text: input.text
    property alias input: input
    property string placeholder: ""
    property bool password: false
    signal accepted(string text)

    width: parent ? parent.width : 0
    implicitHeight: 32
    radius: Theme.radiusSmall
    color: Qt.rgba(1, 1, 1, 0.06)
    border.width: 1
    border.color: input.activeFocus ? Theme.accent : Qt.rgba(1, 1, 1, 0.10)
    Behavior on border.color { ColorAnimation { duration: Theme.animFast } }

    TextInput {
        id: input
        anchors.fill: parent
        anchors.leftMargin: 10
        anchors.rightMargin: 10
        verticalAlignment: TextInput.AlignVCenter
        color: Theme.fg0
        selectionColor: Theme.accent
        font.family: Theme.fontSans
        font.pixelSize: 12
        echoMode: box.password ? TextInput.Password : TextInput.Normal
        clip: true
        onAccepted: box.accepted(text)
        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: !input.text && !input.activeFocus
            text: box.placeholder
            color: Theme.fg3
            font: input.font
        }
    }
}
