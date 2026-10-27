// ui/ListRow.qml — one selectable row in a panel list: glyph, label, an
// optional detail on the right. `active` paints it as the current choice.
import QtQuick
import "../theme"

Rectangle {
    id: row
    property string glyph: ""
    property string label: ""
    property string detail: ""
    property bool active: false
    property bool dim: false
    property color glyphColor: active ? Theme.accentBright : Theme.fg1
    signal clicked()
    signal rightClicked()

    width: parent ? parent.width : 0
    implicitHeight: 34
    radius: Theme.radiusSmall
    color: active ? Theme.selectFill : (hov.hovered ? Theme.hoverFill : "transparent")
    opacity: dim ? 0.55 : 1
    Behavior on color { ColorAnimation { duration: Theme.animFast } }
    scale: tap.pressed ? 0.98 : 1
    Behavior on scale { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }

    Text {
        id: g
        anchors.left: parent.left
        anchors.leftMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        width: row.glyph !== "" ? 20 : 0
        text: row.glyph
        color: row.glyphColor
        font.family: Theme.fontMono
        font.pixelSize: 13
    }
    Text {
        anchors.left: g.right
        anchors.leftMargin: row.glyph !== "" ? 8 : 0
        anchors.right: d.left
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        text: row.label
        color: Theme.fg0
        font.family: Theme.fontSans
        font.pixelSize: 12
        elide: Text.ElideRight
    }
    Text {
        id: d
        anchors.right: parent.right
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        text: row.detail
        color: Theme.fg2
        font.family: Theme.fontMono
        font.pixelSize: 10
    }
    HoverHandler { id: hov; cursorShape: Qt.PointingHandCursor }
    TapHandler { id: tap; onTapped: row.clicked() }
    TapHandler { acceptedButtons: Qt.RightButton; onTapped: row.rightClicked() }
}
