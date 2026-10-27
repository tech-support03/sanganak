// bars/EdgeBar.qml — the right-edge bezel bar.
//
// At rest it is a 2px input strip on the right screen edge. Touching the edge
// slides out a solid black band that runs the full height and reads as more
// monitor bezel: at both ends a concave fillet curves into the top and bottom
// edges, and while the band is out the two far corners are rounded by small
// black corner pieces, so all four screen corners share one radius
// (Theme.screenRadius).
//
// Clicking empty band space pins it on that monitor: it stays out and reserves
// its width so windows move aside. A chevron at the top unpins, and Escape
// unpins while the pointer is on the band. The band also stays out while one
// of its panels is open (services/Panels.qml).
//
// Sections, top to bottom: start (logo, workspaces), centre (indicators,
// clock, weather, …), end (system, connectivity, power).
import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import "../theme"
import "../services" as Services
import "widgets" as W
import "../panels" as P

Scope {
    id: root

    readonly property int revealStrip: 2
    readonly property int hideDelay: 250

    Variants {
        model: Quickshell.screens

        Scope {
            id: perScreen
            required property var modelData
            readonly property string screenName: modelData.name

            PanelWindow {
                id: bar
                screen: perScreen.modelData
                anchors { top: true; bottom: true; right: true }
                implicitWidth: Theme.barSize + Theme.screenRadius
                color: "transparent"
                WlrLayershell.namespace: "sanganak-bar"
                WlrLayershell.layer: WlrLayer.Top
                // Peeking overlays windows; pinned reserves the band's depth.
                exclusionMode: pinned ? ExclusionMode.Normal : ExclusionMode.Ignore
                exclusiveZone: pinned ? Theme.barSize : 0
                // Escape needs keyboard focus; take it only while the pointer
                // is on a pinned band, so typing elsewhere is never stolen.
                WlrLayershell.keyboardFocus: pinned && edgeHover.hovered ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

                property bool pinned: false
                property bool suppressReveal: false
                function unpin() { pinned = false; suppressReveal = true }

                readonly property bool wantReveal: pinned || (!suppressReveal && (edgeHover.hovered
                                                   || Services.Panels.openOn(perScreen.screenName)))
                property bool shown: false
                onWantRevealChanged: {
                    if (wantReveal) { hideTimer.stop(); shown = true }
                    else if (suppressReveal) { hideTimer.stop(); shown = false }
                    else hideTimer.restart()
                }
                Timer { id: hideTimer; interval: root.hideDelay; onTriggered: if (!bar.wantReveal) bar.shown = false }
                Connections {
                    target: edgeHover
                    function onHoveredChanged() { if (!edgeHover.hovered) bar.suppressReveal = false }
                }

                // 0 = tucked into the bezel, 1 = fully out.
                property real reveal: shown ? 1 : 0
                Behavior on reveal { NumberAnimation { duration: 340; easing.type: Easing.OutExpo } }

                mask: Region { item: hit }

                Item {
                    id: hit
                    readonly property real thickness: bar.shown ? Theme.barSize + 8 : root.revealStrip
                    anchors { top: parent.top; bottom: parent.bottom; right: parent.right }
                    width: thickness
                    HoverHandler { id: edgeHover }
                    focus: true
                    Keys.onEscapePressed: if (bar.pinned) bar.unpin()

                    // Everything visible; slides right into the edge as reveal drops.
                    Item {
                        id: sheet
                        x: -(bar.width - hit.width) + (1 - bar.reveal) * (Theme.barSize + Theme.screenRadius)
                        width: bar.width
                        height: bar.height
                        visible: bar.reveal > 0.001

                        // The band with a concave fillet at each end.
                        Shape {
                            id: bandShape
                            anchors.fill: parent
                            preferredRendererType: Shape.CurveRenderer
                            readonly property real w: width
                            readonly property real h: height
                            readonly property real d: Theme.barSize
                            readonly property real f: Theme.screenRadius
                            ShapePath {
                                fillColor: Theme.bezel
                                strokeWidth: -1
                                startX: bandShape.w; startY: 0
                                PathLine { x: bandShape.w - bandShape.d - bandShape.f; y: 0 }
                                PathArc { x: bandShape.w - bandShape.d; y: bandShape.f; radiusX: bandShape.f; radiusY: bandShape.f; direction: PathArc.Clockwise }
                                PathLine { x: bandShape.w - bandShape.d; y: bandShape.h - bandShape.f }
                                PathArc { x: bandShape.w - bandShape.d - bandShape.f; y: bandShape.h; radiusX: bandShape.f; radiusY: bandShape.f; direction: PathArc.Clockwise }
                                PathLine { x: bandShape.w; y: bandShape.h }
                                PathLine { x: bandShape.w; y: 0 }
                            }
                        }

                        // Widgets live in the band proper.
                        Item {
                            id: band
                            anchors { top: parent.top; bottom: parent.bottom; right: parent.right }
                            anchors.topMargin: Theme.screenRadius + unpin.height
                            anchors.bottomMargin: Theme.screenRadius
                            width: Theme.barSize
                            opacity: bar.reveal

                            // Click empty band space to pin.
                            TapHandler { onTapped: if (!bar.pinned) bar.pinned = true }

                            Column {
                                id: startSection
                                anchors.top: parent.top
                                anchors.horizontalCenter: parent.horizontalCenter
                                spacing: 6
                                W.Logo { }
                                W.Workspaces { screenName: perScreen.screenName }
                            }

                            Column {
                                id: centreSection
                                anchors.centerIn: parent
                                spacing: 4
                                W.Indicators { }
                                W.KeyboardLayout { }
                                W.Clock { }
                                W.WeatherButton { }
                                W.MenuButton { }
                                W.UpdateButton { }
                            }

                            Column {
                                id: endSection
                                anchors.bottom: parent.bottom
                                anchors.horizontalCenter: parent.horizontalCenter
                                spacing: 2
                                W.SysMon { }
                                W.Tray { }
                                W.DisplayButton { }
                                W.AgentsButton { }
                                W.BluetoothButton { }
                                W.NetworkButton { }
                                W.AudioButton { }
                                W.BatteryButton { }
                                W.PowerButton { }
                            }
                        }

                        // Unpin chevron, only while pinned.
                        Item {
                            id: unpin
                            anchors.right: parent.right
                            y: Theme.screenRadius
                            width: Theme.barSize
                            height: bar.pinned ? Theme.barSlot : 0
                            clip: true
                            opacity: bar.pinned ? bar.reveal : 0
                            Behavior on height { NumberAnimation { duration: Theme.animMed; easing.type: Easing.OutCubic } }
                            Behavior on opacity { NumberAnimation { duration: Theme.animFast } }
                            Rectangle {
                                anchors.centerIn: parent
                                width: 30; height: 30; radius: 15
                                color: Qt.rgba(1, 1, 1, unpinArea.containsMouse ? 0.12 : 0)
                                Behavior on color { ColorAnimation { duration: Theme.animFast } }
                                Text {
                                    anchors.centerIn: parent
                                    text: ""   // chevron-right: into the edge
                                    color: Theme.fg0
                                    opacity: unpinArea.containsMouse ? 1 : 0.6
                                    font.family: Theme.fontMono
                                    font.pixelSize: 13
                                }
                            }
                            MouseArea {
                                id: unpinArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: bar.unpin()
                            }
                        }
                    }
                }
            }

            // Rounded far corners (top-left, bottom-left) while the band is out.
            PanelWindow {
                id: corners
                screen: perScreen.modelData
                anchors { top: true; bottom: true; left: true }
                implicitWidth: Theme.screenRadius
                color: "transparent"
                exclusionMode: ExclusionMode.Ignore
                exclusiveZone: 0
                mask: Region { }
                WlrLayershell.namespace: "sanganak-bar-corners"
                WlrLayershell.layer: WlrLayer.Top
                property real anim: bar.shown ? 1 : 0
                Behavior on anim { NumberAnimation { duration: 340; easing.type: Easing.OutExpo } }
                visible: anim > 0.001

                component Corner: Shape {
                    id: corner
                    property bool atBottom: false
                    width: Theme.screenRadius; height: Theme.screenRadius
                    preferredRendererType: Shape.CurveRenderer
                    ShapePath {
                        fillColor: Theme.bezel
                        strokeWidth: -1
                        startX: 0; startY: corner.atBottom ? Theme.screenRadius : 0
                        PathLine { x: 0; y: corner.atBottom ? 0 : Theme.screenRadius }
                        PathArc {
                            x: Theme.screenRadius; y: corner.atBottom ? Theme.screenRadius : 0
                            radiusX: Theme.screenRadius; radiusY: Theme.screenRadius
                            direction: corner.atBottom ? PathArc.Counterclockwise : PathArc.Clockwise
                        }
                        PathLine { x: 0; y: corner.atBottom ? Theme.screenRadius : 0 }
                    }
                }
                Corner { anchors.top: parent.top; opacity: corners.anim }
                Corner { anchors.bottom: parent.bottom; atBottom: true; opacity: corners.anim }
            }

            // This screen's panels.
            P.AudioPanel { targetScreen: perScreen.modelData }
            P.NetworkPanel { targetScreen: perScreen.modelData }
            P.BluetoothPanel { targetScreen: perScreen.modelData }
            P.CalendarPanel { targetScreen: perScreen.modelData }
            P.WeatherPanel { targetScreen: perScreen.modelData }
            P.DisplayPanel { targetScreen: perScreen.modelData }
            P.BatteryPanel { targetScreen: perScreen.modelData }
            P.AgentsPanel { targetScreen: perScreen.modelData }
            P.SysMonPanel { targetScreen: perScreen.modelData }
            P.UpdatesPanel { targetScreen: perScreen.modelData }
            P.MenuPanel { targetScreen: perScreen.modelData }
        }
    }
}
