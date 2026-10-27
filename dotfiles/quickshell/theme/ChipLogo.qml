// ChipLogo — the संगणक mark: the Sahyadri ridge on a chip.
//
// Drawn on a 24-unit grid and scaled by `size`, so it stays crisp at any
// sidebar scale. Every colour is a Theme token, so it re-themes live:
//   body = Theme.base (same black as the bar; a faint c2 hairline keeps the
//   outline readable on it) · pins + ridge = c2 · sun = accent · ground = c3.
import QtQuick
import QtQuick.Shapes

Item {
    id: logo
    property real size: 30
    readonly property real u: size / 24

    width: size
    height: size

    // Pins: two per side, behind the body.
    Repeater {
        model: [
            [7, 1, 2, 4], [15, 1, 2, 4], [7, 19, 2, 4], [15, 19, 2, 4],
            [1, 7, 4, 2], [1, 15, 4, 2], [19, 7, 4, 2], [19, 15, 4, 2]
        ]
        delegate: Rectangle {
            required property var modelData
            x: modelData[0] * logo.u
            y: modelData[1] * logo.u
            width: modelData[2] * logo.u
            height: modelData[3] * logo.u
            radius: logo.u
            color: Theme.c2
            Behavior on color { ColorAnimation { duration: Theme.animMed } }
        }
    }

    Rectangle {
        x: 4 * logo.u
        y: 4 * logo.u
        width: 16 * logo.u
        height: 16 * logo.u
        radius: 4 * logo.u
        color: Theme.base
        border.color: Theme.tint(Theme.c2, 0.22)
        border.width: Math.max(1, 0.5 * logo.u)
        Behavior on color { ColorAnimation { duration: Theme.animMed } }
    }

    // Sun.
    Rectangle {
        x: 7.2 * logo.u
        y: 7.2 * logo.u
        width: 3.6 * logo.u
        height: width
        radius: width / 2
        color: Theme.accent
        Behavior on color { ColorAnimation { duration: Theme.animMed } }
    }

    // Ridge.
    Shape {
        anchors.fill: parent
        antialiasing: true
        ShapePath {
            strokeColor: Theme.c2
            strokeWidth: 1.6 * logo.u
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            startX: 7 * logo.u;    startY: 15.6 * logo.u
            PathLine { x: 10 * logo.u;   y: 11.6 * logo.u }
            PathLine { x: 12 * logo.u;   y: 13.6 * logo.u }
            PathLine { x: 14.5 * logo.u; y: 10.1 * logo.u }
            PathLine { x: 17 * logo.u;   y: 14.6 * logo.u }
        }
    }

    // Ground line.
    Rectangle {
        x: 7 * logo.u
        y: 17.4 * logo.u
        width: 10 * logo.u
        height: 1.1 * logo.u
        radius: height / 2
        color: Theme.c3
        Behavior on color { ColorAnimation { duration: Theme.animMed } }
    }
}
