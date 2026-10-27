// ~/.config/quickshell/overlays/RgbControl.qml — PC RGB control panel.
//
// Triggered by `qs ipc call rgb toggle` (wired to Mod+Shift+R in niri). Same
// overlay idiom as ThemePicker/PowerFlyout: full-screen Overlay layer, dim
// backdrop, click-outside / Escape closes, exclusive keyboard focus.
//
// This is a thin, intuitive UI over `~/.local/bin/pc-rgb` — the hardened engine
// that resolves RAM + motherboard-fan devices BY NAME and persists the choice to
// ~/.config/OpenRGB/pc-rgb.conf (re-applied at login by openrgb.service). Because
// everything routes through pc-rgb, the PC-only guarantee holds: the Wooting is
// disabled in OpenRGB.json and never touched here. Colours chosen here are RAW
// HARDWARE colours (your fans/RAM), independent of the rice Theme palette — so
// the swatches are literal, NOT Theme tokens. Only the panel chrome uses Theme.
//
// Modes map 1:1 to pc-rgb verbs: static / breathing / flashing (need a colour),
// rainbow / off (don't). Picking a colour while in rainbow/off snaps to static.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../theme"

Scope {
    id: scope

    property bool  active: false
    property string selMode: "static"          // static|breathing|flashing|rainbow|off
    property color selColor: "#8000FF"
    property real  hueValue: 0.78              // slider positions (0..1), source for recolor
    property real  brightnessValue: 1.0

    readonly property bool colorMode: selMode !== "rainbow" && selMode !== "off"

    // Curated LED-friendly swatches. Vivid (pale colours read as white on LEDs).
    readonly property var presets: [
        "#FF0000", "#FF6A00", "#FF9500", "#FFD000", "#8CFF00", "#00FF4C",
        "#00FFC8", "#00E5FF", "#2060FF", "#5B6EE0", "#8000FF", "#FF33CC"
    ]

    function open()   { panel.visible = true; active = true;
                        Qt.callLater(() => content.forceActiveFocus()) }
    function close()  { active = false; hideTimer.restart() }
    function toggle() { active ? close() : open() }

    // --- color helpers -----------------------------------------------------
    function hex6(c) {
        function h(x) { var s = Math.round(x * 255).toString(16); return s.length < 2 ? "0" + s : s }
        return (h(c.r) + h(c.g) + h(c.b)).toUpperCase()
    }
    function syncSlidersFromColor() {
        if (selColor.hsvHue >= 0) scope.hueValue = selColor.hsvHue
        scope.brightnessValue = selColor.hsvValue
    }
    function recolorFromSliders() {
        scope.selColor = Qt.hsva(scope.hueValue, 1.0, scope.brightnessValue, 1.0)
    }

    // --- hardware apply (routes through pc-rgb; persists + re-applied at login)
    function applyNow() {
        var cmd = scope.selMode === "rainbow" ? "rainbow"
                : scope.selMode === "off"     ? "off"
                : scope.selMode + " " + scope.hex6(scope.selColor)
        Quickshell.execDetached(["sh", "-c",
            "\"$HOME/.local/bin/pc-rgb\" " + cmd + " 2>>\"$HOME/.cache/qs-rgb.log\""])
    }
    function setMode(m)     { scope.selMode = m; scope.applyNow() }
    function commitColor()  { if (!scope.colorMode) scope.selMode = "static"; scope.applyNow() }
    function pickPreset(hex){ scope.selColor = hex; scope.syncSlidersFromColor(); scope.commitColor() }

    // Reflect the current saved state on open (and live if pc-rgb is used elsewhere).
    function loadConf(t) {
        var m = (t || "").match(/MODE=([A-Za-z]+)/)
        var c = (t || "").match(/COLOR=([0-9a-fA-F]{6})/)
        if (m) scope.selMode = m[1].toLowerCase()
        if (c) { scope.selColor = "#" + c[1]; scope.syncSlidersFromColor() }
    }

    Timer { id: hideTimer; interval: 220; onTriggered: if (!scope.active) panel.visible = false }

    FileView {
        path: Quickshell.env("HOME") + "/.config/OpenRGB/pc-rgb.conf"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: scope.loadConf(text())
    }

    IpcHandler {
        target: "rgb"
        function toggle(): void { scope.toggle() }
        function show(): void   { scope.open() }
        function hide(): void   { scope.close() }
    }

    PanelWindow {
        id: panel
        visible: false
        color: "transparent"
        anchors { top: true; bottom: true; left: true; right: true }
        exclusiveZone: -1
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "quickshell-rgb"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

        Rectangle {
            anchors.fill: parent
            color: Theme.tint(Theme.baseDeep, 0.55)
            opacity: scope.active ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.animMed; easing.type: Easing.OutQuad } }
            MouseArea { anchors.fill: parent; onClicked: scope.close() }
        }

        Item {
            id: content
            anchors.fill: parent
            focus: true
            opacity: scope.active ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.animMed; easing.type: Easing.OutQuad } }
            Keys.onEscapePressed: scope.close()

            Rectangle {
                id: card
                anchors.centerIn: parent
                width: 360
                implicitHeight: col.implicitHeight + 28
                radius: Theme.radius
                color: Theme.tint(Theme.baseRaised, 0.55)
                border.color: Theme.line
                border.width: 1
                scale: scope.active ? 1.0 : 0.94
                Behavior on scale { NumberAnimation { duration: Theme.animMed; easing.type: Easing.OutCubic } }

                Column {
                    id: col
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 12

                    // --- header ------------------------------------------------
                    Item {
                        width: parent.width
                        height: 18
                        Text {
                            anchors.left: parent.left
                            text: "RGB"
                            color: Theme.fg2
                            font.family: Theme.fontSans
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                        }
                        Text {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: scope.colorMode ? ("#" + scope.hex6(scope.selColor)) : scope.selMode.toUpperCase()
                            color: Theme.fg2
                            font.family: Theme.fontMono
                            font.pixelSize: 11
                        }
                    }

                    // --- mode pills -------------------------------------------
                    Flow {
                        width: parent.width
                        spacing: 6
                        Repeater {
                            model: [
                                { m: "static",    label: "Static" },
                                { m: "breathing", label: "Breathing" },
                                { m: "flashing",  label: "Flashing" },
                                { m: "rainbow",   label: "Rainbow" },
                                { m: "off",       label: "Off" }
                            ]
                            delegate: Rectangle {
                                id: pill
                                required property var modelData
                                readonly property bool sel: scope.selMode === modelData.m
                                width: plabel.implicitWidth + 24
                                height: 30
                                radius: 15
                                color: sel ? Theme.accent
                                           : (ph.hovered ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(1, 1, 1, 0.04))
                                Behavior on color { ColorAnimation { duration: Theme.animFast } }
                                scale: pm.pressed ? 0.95 : 1.0
                                Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

                                Text {
                                    id: plabel
                                    anchors.centerIn: parent
                                    text: pill.modelData.label
                                    color: pill.sel ? Theme.base : Theme.fg1
                                    font.family: Theme.fontSans
                                    font.pixelSize: 12
                                    font.weight: pill.sel ? Font.DemiBold : Font.Normal
                                }
                                HoverHandler { id: ph }
                                MouseArea {
                                    id: pm
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: scope.setMode(pill.modelData.m)
                                }
                            }
                        }
                    }

                    // --- colour section (dim + inert for rainbow/off) ----------
                    Column {
                        width: parent.width
                        spacing: 12
                        opacity: scope.colorMode ? 1.0 : 0.35
                        enabled: scope.colorMode
                        Behavior on opacity { NumberAnimation { duration: Theme.animFast } }

                        // preview + swatches
                        Row {
                            width: parent.width
                            spacing: 10
                            Rectangle {
                                width: 46; height: 46; radius: 12
                                color: scope.selColor
                                border.color: Theme.line
                                border.width: 1
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Grid {
                                anchors.verticalCenter: parent.verticalCenter
                                columns: 6
                                rowSpacing: 8
                                columnSpacing: 8
                                Repeater {
                                    model: scope.presets
                                    delegate: Rectangle {
                                        id: sw
                                        required property var modelData
                                        readonly property bool sel: scope.hex6(scope.selColor) === scope.hex6(modelData)
                                        width: 40; height: 17; radius: 6
                                        color: modelData
                                        border.color: sel ? Theme.fg0 : Qt.rgba(1, 1, 1, 0.14)
                                        border.width: sel ? 2 : 1
                                        scale: sm.pressed ? 0.92 : 1.0
                                        Behavior on scale { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }
                                        MouseArea {
                                            id: sm
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: scope.pickPreset(sw.modelData)
                                        }
                                    }
                                }
                            }
                        }

                        // hue slider
                        Column {
                            width: parent.width
                            spacing: 5
                            Text { text: "Hue"; color: Theme.fg2; font.family: Theme.fontSans; font.pixelSize: 11 }
                            Rectangle {
                                id: hueTrack
                                width: parent.width; height: 16; radius: 8
                                gradient: Gradient {
                                    orientation: Gradient.Horizontal
                                    GradientStop { position: 0.000; color: "#ff0000" }
                                    GradientStop { position: 0.167; color: "#ffff00" }
                                    GradientStop { position: 0.333; color: "#00ff00" }
                                    GradientStop { position: 0.500; color: "#00ffff" }
                                    GradientStop { position: 0.667; color: "#0000ff" }
                                    GradientStop { position: 0.833; color: "#ff00ff" }
                                    GradientStop { position: 1.000; color: "#ff0000" }
                                }
                                Rectangle {   // handle
                                    width: 18; height: 18; radius: 9
                                    color: "white"; border.color: Qt.rgba(0, 0, 0, 0.35); border.width: 1
                                    y: -1
                                    x: Math.max(0, Math.min(hueTrack.width - width, scope.hueValue * hueTrack.width - width / 2))
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    onPressed:  (e) => { scope.hueValue = Math.max(0, Math.min(1, e.x / width)); scope.recolorFromSliders() }
                                    onPositionChanged: (e) => { scope.hueValue = Math.max(0, Math.min(1, e.x / width)); scope.recolorFromSliders() }
                                    onReleased: scope.commitColor()
                                }
                            }
                        }

                        // brightness slider
                        Column {
                            width: parent.width
                            spacing: 5
                            Text { text: "Brightness"; color: Theme.fg2; font.family: Theme.fontSans; font.pixelSize: 11 }
                            Rectangle {
                                id: briTrack
                                width: parent.width; height: 16; radius: 8
                                gradient: Gradient {
                                    orientation: Gradient.Horizontal
                                    GradientStop { position: 0.0; color: "#000000" }
                                    GradientStop { position: 1.0; color: Qt.hsva(scope.hueValue, 1, 1, 1) }
                                }
                                Rectangle {   // handle
                                    width: 18; height: 18; radius: 9
                                    color: "white"; border.color: Qt.rgba(0, 0, 0, 0.35); border.width: 1
                                    y: -1
                                    x: Math.max(0, Math.min(briTrack.width - width, scope.brightnessValue * briTrack.width - width / 2))
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    onPressed:  (e) => { scope.brightnessValue = Math.max(0.04, Math.min(1, e.x / width)); scope.recolorFromSliders() }
                                    onPositionChanged: (e) => { scope.brightnessValue = Math.max(0.04, Math.min(1, e.x / width)); scope.recolorFromSliders() }
                                    onReleased: scope.commitColor()
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
