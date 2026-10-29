// Display: the screen this panel opened on — brightness (with its "mood"),
// the UI text size, and scale — then every display with its mode, where a
// click switches it on or off. Data and writes live in services/Display.qml.
import QtQuick
import Quickshell
import "../theme"
import "../ui"
import "../services" as Services

Panel {
    id: p
    panelId: "display"
    readonly property var disp: Services.Display
    readonly property string here: targetScreen ? targetScreen.name : ""
    readonly property var out: disp.output(here)
    readonly property bool dimmable: disp.hasBrightness(here)
    title: "Display"
    glyph: "󰍹"
    subtitle: dimmable ? disp.mood(disp.level[here]) : "fixed brightness"
    onOpenChanged: if (open) disp.refresh()

    // ---- brightness --------------------------------------------------------
    SectionLabel {
        text: "Brightness"
        value: p.dimmable ? p.disp.level[p.here] + "%" : ""
    }
    Slider {
        width: parent.width
        visible: p.dimmable
        value: p.dimmable ? p.disp.level[p.here] / 100 : 0
        onMoved: function (v) { p.disp.setBrightness(p.here, v * 100) }
    }
    Text {
        width: parent.width
        visible: !p.dimmable
        text: p.out && !p.out.internal ? p.here + " doesn't answer DDC/CI brightness (check the monitor's OSD for a DDC/CI switch)."
                                       : "No brightness control on this display."
        color: Theme.fg3
        font.family: Theme.fontSans
        font.pixelSize: 10
        wrapMode: Text.Wrap
    }

    // ---- text size ---------------------------------------------------------
    SectionLabel { text: "Text size"; value: p.disp.textSize + "px" }
    Slider {
        id: textSlider
        width: parent.width
        readonly property var stops: p.disp.textSizes
        step: 1 / (stops.length - 1)
        value: Math.max(0, stops.indexOf(p.disp.textSize)) / (stops.length - 1)
        onMoved: function (v) {
            var px = stops[Math.round(v * (stops.length - 1))]
            if (px !== p.disp.textSize) p.disp.setTextSize(px)
        }
    }

    // ---- scale -------------------------------------------------------------
    SectionLabel { text: "Scale"; value: p.disp.enabledCount > 1 ? p.here : "" }
    Row {
        spacing: 4
        Repeater {
            model: p.disp.validScales(p.out)
            Rectangle {
                required property var modelData
                readonly property bool on: p.out && Math.abs(p.out.scale - modelData) < 0.01
                width: 48; height: 24; radius: 12
                color: on ? Theme.selectFill : (h.hovered ? Theme.hoverFill : Qt.rgba(1, 1, 1, 0.04))
                Behavior on color { ColorAnimation { duration: Theme.animFast } }
                scale: t.pressed ? 0.94 : 1
                Behavior on scale { NumberAnimation { duration: Theme.animFast } }
                Text { anchors.centerIn: parent; text: modelData + "×"; color: Theme.fg0; font.family: Theme.fontMono; font.pixelSize: 10 }
                HoverHandler { id: h; cursorShape: Qt.PointingHandCursor }
                TapHandler { id: t; onTapped: p.disp.setScale(p.here, modelData) }
            }
        }
    }

    // ---- every display -------------------------------------------------------
    SectionLabel { text: "Displays"; value: p.disp.enabledCount + " of " + p.disp.outputs.length + " on" }
    Repeater {
        model: p.disp.outputs
        ListRow {
            required property var modelData
            glyph: "󰍹"
            label: modelData.name + "   " + modelData.model      // highlighted = this screen
            detail: modelData.enabled
                    ? modelData.width + "×" + modelData.height + " · " + modelData.refresh + " Hz"
                      + (modelData.scale !== 1 ? " · " + modelData.scale + "×" : "") + (modelData.vrr ? " · VRR" : "")
                    : "off"
            active: modelData.name === p.here
            dim: !modelData.enabled || !p.disp.canToggle(modelData)
            onClicked: p.disp.setEnabled(modelData.name, !modelData.enabled)
        }
    }
    Text {
        width: parent.width
        visible: p.disp.outputs.length > 1
        text: "Click a display to switch it on or off."
        color: Theme.fg3
        font.family: Theme.fontSans
        font.pixelSize: 9
    }
    ListRow {
        glyph: "󰍺"
        label: "Arrange displays (nwg-displays)"
        onClicked: { Quickshell.execDetached(["nwg-displays"]); Services.Panels.close() }
    }
}
