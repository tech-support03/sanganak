// ui/Panel.qml — a card that opens out of the edge bar.
//
// One instance per screen per panel (create it inside the bar's Variants).
// The card is the bezel black with a 1px accent edge, slides out of the bar
// and fades, and closes on Escape or a click anywhere outside it. The bar
// itself stays clickable while a panel is open: the click-catcher's input
// region has the bar's strip cut out of it.
//
//   Panel { panelId: "audio"; screen: modelData; title: "Audio"; ... content ... }
import QtQuick
import Quickshell
import Quickshell.Wayland
import "../theme"
import "../services" as Services

PanelWindow {
    id: win

    required property string panelId
    // The screen this copy lives on (set by the bar). Read from here, not
    // from `screen`, which the window re-evaluates while mapping.
    required property var targetScreen
    screen: targetScreen
    property string title: ""
    property string subtitle: ""
    property string glyph: ""
    property int cardWidth: Theme.panelWidth
    // Header switch (e.g. Wi-Fi radio, Bluetooth power). Hidden unless set.
    property bool showSwitch: false
    property bool switchOn: false
    signal switchToggled()
    // Content goes in the card body, below the header.
    default property alias content: body.data
    readonly property alias body: body

    readonly property bool open: Services.Panels.openId === panelId
                                 && Services.Panels.openScreen === (targetScreen ? targetScreen.name : "")
    property bool shown: false
    onOpenChanged: {
        if (open) { closeTimer.stop(); shown = true; Qt.callLater(function () { keys.forceActiveFocus() }) }
        else closeTimer.restart()
    }
    Timer { id: closeTimer; interval: Theme.animMed + 40; onTriggered: if (!win.open) win.shown = false }

    visible: shown
    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    exclusiveZone: 0
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "sanganak-panel"
    // Exclusive while open: a panel summoned by a keybind has to take typing
    // and Escape at once (OnDemand only focuses after a click on it). A click
    // outside closes the panel, which hands the keyboard straight back.
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // Everything but the bar strip takes input: outside the card it closes.
    mask: Region {
        item: catcher
        Region { item: barHole; intersection: Intersection.Subtract }
    }
    Item { id: catcher; anchors.fill: parent }
    Item { id: barHole; anchors { top: parent.top; bottom: parent.bottom; right: parent.right } width: Theme.barSize }

    MouseArea {
        anchors.fill: parent
        onPressed: Services.Panels.close()
    }

    // Vertical placement: centred on the summoning icon, clamped on screen.
    readonly property real wantY: Services.Panels.anchorY >= 0
        ? Services.Panels.anchorY - card.height / 2
        : (height - card.height) / 2
    readonly property real progress: open ? 1 : 0

    Rectangle {
        id: card
        width: win.cardWidth
        height: Math.min(win.height - 2 * Theme.gap, column.implicitHeight + 28)
        x: win.width - Theme.barSize - Theme.gap - width + (1 - slide.p) * 24
        y: Math.max(Theme.gap, Math.min(win.height - height - Theme.gap, win.wantY))
        radius: Theme.radius
        color: Theme.panelBg
        border.width: 1
        border.color: Theme.panelEdge
        opacity: slide.p
        clip: true

        QtObject { id: slide; property real p: win.progress
            Behavior on p { NumberAnimation { duration: Theme.animMed; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.2, 0.85, 0.25, 1.0, 1, 1] } } }
        Behavior on height { NumberAnimation { duration: Theme.animMed; easing.type: Easing.OutCubic } }

        // Swallow clicks so they don't reach the close catcher behind.
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onPressed: function (m) { m.accepted = true } }

        Flickable {
            anchors.fill: parent
            anchors.margins: 14
            contentHeight: column.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            clip: true

            Column {
                id: column
                width: parent.width
                spacing: 12

                // ---- header: glyph, title / subtitle, optional switch -----
                Item {
                    width: parent.width
                    height: win.title !== "" ? 40 : 0
                    visible: win.title !== ""

                    Text {
                        id: hGlyph
                        anchors.verticalCenter: parent.verticalCenter
                        text: win.glyph
                        color: Theme.fg0
                        font.family: Theme.fontMono
                        font.pixelSize: 18
                        width: win.glyph !== "" ? 26 : 0
                    }
                    Column {
                        anchors.left: hGlyph.right
                        anchors.leftMargin: win.glyph !== "" ? 8 : 0
                        anchors.right: hSwitch.left
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2
                        Text {
                            width: parent.width
                            text: win.title
                            color: Theme.fg0
                            font.family: Theme.fontSans
                            font.pixelSize: 14
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }
                        Text {
                            width: parent.width
                            visible: win.subtitle !== ""
                            text: win.subtitle.toUpperCase()
                            color: Theme.fg2
                            font.family: Theme.fontSans
                            font.pixelSize: 9
                            font.letterSpacing: 1.4
                            elide: Text.ElideRight
                        }
                    }
                    Toggle {
                        id: hSwitch
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        visible: win.showSwitch
                        width: win.showSwitch ? implicitWidth : 0
                        checked: win.switchOn
                        onToggled: win.switchToggled()
                    }
                }

                Rectangle { width: parent.width; height: 1; color: Theme.line; visible: win.title !== "" }

                Column {
                    id: body
                    width: parent.width
                    spacing: 10
                }
            }
        }
    }

    Item {
        id: keys
        focus: true
        Keys.onEscapePressed: Services.Panels.close()
    }
}
