// Network: status of the active uplink, the Wi-Fi radio (header switch),
// wired override, and the scan list with inline passwords. iwd + networkd
// through services/Network.qml — no NetworkManager.
import QtQuick
import Quickshell
import "../theme"
import "../ui"
import "../services" as Services

Panel {
    id: p
    panelId: "network"
    readonly property var net: Services.Network
    title: net.primaryType === "ethernet" ? "Ethernet" : net.primaryType === "wifi" ? net.primaryName : "Offline"
    subtitle: net.connected ? (net.localIp || "connected") : (net.wifiEnabled ? "not connected" : "wi-fi off")
    glyph: net.glyph
    // The Wi-Fi radio switch and list only exist with a Wi-Fi adapter.
    showSwitch: net.wifiPresent
    switchOn: net.wifiEnabled
    onSwitchToggled: net.toggleWifi()

    property string expanded: ""
    property string status: ""
    onOpenChanged: if (open) net.rescan()
    Connections { target: p.net; function onActionFinished(ok, msg) { p.status = ok ? "" : msg } }

    function activate(n) {
        if (n.active) { net.disconnectWifi(); return }
        if (n.enterprise && !n.saved) {
            // 802.1X: iwctl prompts for identity + EAP secrets a PSK box can't.
            Quickshell.execDetached(["alacritty", "--class", "sanganak.float", "-e", "iwctl", "station", net._wifiDev, "connect", n.ssid])
            Services.Panels.close()
            return
        }
        if (!n.secured || n.saved) { net.connectWifi(n.ssid, n.secured, ""); status = "Connecting to " + n.ssid + "…" }
        else expanded = expanded === n.ssid ? "" : n.ssid
    }

    ListRow {
        visible: p.net.ethernetPresent
        glyph: "󰈀"
        label: "Wired"
        detail: !p.net.ethernetPlugged ? "unplugged" : p.net.ethernetEnabled ? "on" : "off"
        active: p.net.ethernetUp
        onClicked: p.net.toggleEthernet()
    }

    SectionLabel { text: "Wi-Fi networks"; value: p.net.scanning ? "scanning…" : ""; visible: p.net.wifiPresent && p.net.wifiEnabled }
    Repeater {
        model: p.net.wifiPresent && p.net.wifiEnabled ? p.net.networks : []
        Column {
            required property var modelData
            width: parent.width
            spacing: 4
            ListRow {
                glyph: p.net.signalGlyph(modelData.signal)
                label: modelData.ssid
                detail: modelData.active ? "connected" : (modelData.enterprise ? "802.1X" : (modelData.secured ? "" : "open"))
                active: modelData.active
                onClicked: p.activate(modelData)
                onRightClicked: if (modelData.saved) p.net.forget(modelData.ssid)
            }
            TextBox {
                visible: p.expanded === modelData.ssid
                password: true
                placeholder: "Password for " + modelData.ssid
                onVisibleChanged: if (visible) input.forceActiveFocus()
                onAccepted: function (t) {
                    if (!t.length) return
                    p.net.connectWifi(modelData.ssid, true, t)
                    p.status = "Connecting to " + modelData.ssid + "…"
                    p.expanded = ""
                    text = ""
                }
            }
        }
    }
    Text {
        width: parent.width
        visible: p.status !== "" || p.net.lastError !== ""
        text: p.status || p.net.lastError
        color: Theme.fg2
        font.family: Theme.fontSans
        font.pixelSize: 10
        wrapMode: Text.Wrap
    }
    Text {
        width: parent.width
        visible: p.net.wifiPresent
        text: "Right-click a saved network to forget it."
        color: Theme.fg3
        font.family: Theme.fontSans
        font.pixelSize: 9
    }
}
