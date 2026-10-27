// ui/Slider.qml — horizontal level slider (0..1). Drag or click to set;
// wheel nudges by `step`. Emits moved(value) for the owner to apply.
import QtQuick
import "../theme"

Item {
    id: s
    property real value: 0          // 0..1, bound by the owner
    property real step: 0.05
    property color fill: Theme.accent
    signal moved(real value)

    implicitHeight: 18
    readonly property real shown: drag.pressed ? drag.live : Math.max(0, Math.min(1, value))

    Rectangle {
        id: track
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: 6
        radius: 3
        color: Qt.rgba(1, 1, 1, 0.10)
        Rectangle {
            width: Math.max(height, parent.width * s.shown)
            height: parent.height
            radius: 3
            color: s.fill
            Behavior on width { enabled: !drag.pressed; NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }
        }
    }
    Rectangle {
        width: 14; height: 14; radius: 7
        anchors.verticalCenter: parent.verticalCenter
        x: (parent.width - width) * s.shown
        color: Theme.fg0
        scale: drag.pressed || hov.hovered ? 1 : 0.0
        Behavior on scale { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutBack } }
    }
    HoverHandler { id: hov; cursorShape: Qt.PointingHandCursor }
    MouseArea {
        id: drag
        property real live: 0
        anchors.fill: parent
        function at(x) { return Math.max(0, Math.min(1, x / width)) }
        onPressed: function (m) { live = at(m.x); s.moved(live) }
        onPositionChanged: function (m) { if (pressed) { live = at(m.x); s.moved(live) } }
        onWheel: function (w) { s.moved(Math.max(0, Math.min(1, s.value + (w.angleDelta.y > 0 ? s.step : -s.step)))) }
    }
}
