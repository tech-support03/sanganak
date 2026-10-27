// Bluetooth: radio switch, device list (connect / disconnect; right-click to
// forget), scan. Pairing that needs a PIN goes to blueman.
import QtQuick
import Quickshell
import "../theme"
import "../ui"
import "../services" as Services

Panel {
    id: p
    panelId: "bluetooth"
    readonly property var bt: Services.Bluetooth
    title: "Bluetooth"
    subtitle: !bt.powered ? "off" : bt.connectedCount > 0 ? bt.connectedName : "no devices connected"
    glyph: bt.glyph
    showSwitch: true
    switchOn: bt.powered
    onSwitchToggled: bt.togglePower()
    onOpenChanged: if (open && bt.powered) bt.rescan()

    SectionLabel { text: "Devices"; value: p.bt.scanning ? "scanning…" : ""; visible: p.bt.powered }
    Repeater {
        model: p.bt.powered ? p.bt.devices : []
        ListRow {
            required property var modelData
            glyph: modelData.glyph
            label: modelData.name
            detail: modelData.connected ? "connected" : modelData.paired ? "paired" : ""
            active: modelData.connected
            dim: !modelData.paired && !modelData.connected
            onClicked: modelData.connected ? p.bt.disconnect(modelData.mac) : p.bt.connect(modelData.mac, modelData.paired)
            onRightClicked: if (modelData.paired) p.bt.forget(modelData.mac)
        }
    }
    ListRow {
        visible: p.bt.powered
        glyph: "󰑐"
        label: "Scan again"
        onClicked: p.bt.rescan()
    }
    ListRow {
        glyph: "󰒓"
        label: "Pair with PIN (Blueman)"
        onClicked: { Quickshell.execDetached(["blueman-manager"]); Services.Panels.close() }
    }
    Text {
        visible: p.bt.lastError !== ""
        width: parent.width
        text: p.bt.lastError
        color: Theme.fg2
        font.family: Theme.fontSans
        font.pixelSize: 10
        wrapMode: Text.Wrap
    }
}
