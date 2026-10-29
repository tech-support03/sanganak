// Network: status of the active uplink, the Wi-Fi radio (header switch),
// wired override, a built-in speed test (services/SpeedTest.qml), the DNS
// provider (services/Dns.qml), and the scan list with inline passwords. iwd +
// networkd through services/Network.qml — no NetworkManager.
import QtQuick
import Quickshell
import "../theme"
import "../ui"
import "../services" as Services

Panel {
    id: p
    panelId: "network"
    readonly property var net: Services.Network
    readonly property var speed: Services.SpeedTest
    readonly property var dns: Services.Dns
    title: net.primaryType === "ethernet" ? "Ethernet" : net.primaryType === "wifi" ? net.primaryName : "Offline"
    subtitle: net.connected ? (net.localIp || "connected") : (net.wifiEnabled ? "not connected" : "wi-fi off")
    glyph: net.glyph
    // The Wi-Fi radio switch and list only exist with a Wi-Fi adapter.
    showSwitch: net.wifiPresent
    switchOn: net.wifiEnabled
    onSwitchToggled: net.toggleWifi()

    property string expanded: ""
    property string status: ""
    onOpenChanged: if (open) { net.rescan(); dns.refresh() }
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

    // ---- speed test ------------------------------------------------------------
    Item {
        width: parent.width
        height: 20
        visible: p.net.connected || p.speed.phase !== "idle"
        SectionLabel {
            anchors.verticalCenter: parent.verticalCenter
            text: "Speed test"
            value: ""
        }
        Rectangle {
            id: runPill
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: runText.implicitWidth + 20; height: 20; radius: 10
            color: runTap.pressed ? Theme.tint(Theme.accent, 0.32) : (runHov.hovered ? Theme.tint(Theme.accent, 0.24) : Theme.tint(Theme.accent, 0.14))
            Behavior on color { ColorAnimation { duration: Theme.animFast } }
            scale: runTap.pressed ? 0.94 : 1
            Behavior on scale { NumberAnimation { duration: Theme.animFast } }
            Text {
                id: runText
                anchors.centerIn: parent
                text: p.speed.running ? "Stop" : p.speed.phase === "idle" ? "Run" : "Run again"
                color: Theme.accentBright
                font.family: Theme.fontSans
                font.pixelSize: 10
                font.weight: Font.DemiBold
            }
            HoverHandler { id: runHov; cursorShape: Qt.PointingHandCursor }
            TapHandler { id: runTap; onTapped: p.speed.running ? p.speed.stop() : p.speed.run() }
        }
    }
    Row {
        width: parent.width
        spacing: 8
        visible: p.speed.phase !== "idle"
        Repeater {
            model: [
                { key: "down", label: "Download", glyph: "\u2193" },
                { key: "up",   label: "Upload",   glyph: "\u2191" }
            ]
            Rectangle {
                id: tile
                required property var modelData
                readonly property real mbps: p.speed[modelData.key]
                readonly property bool live: p.speed.phase === modelData.key
                // Both bars share one scale: the faster result, at least 100 Mbps.
                readonly property real scaleTop: Math.max(100, p.speed.down, p.speed.up)
                width: (parent.width - 8) / 2
                height: 64
                radius: Theme.radiusSmall
                color: live ? Theme.tint(Theme.accent, 0.10) : Qt.rgba(1, 1, 1, 0.04)
                Behavior on color { ColorAnimation { duration: Theme.animMed } }
                Column {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 4
                    Text {
                        text: tile.modelData.glyph + "  " + tile.modelData.label.toUpperCase()
                        color: tile.live ? Theme.accentBright : Theme.fg2
                        font.family: Theme.fontSans
                        font.pixelSize: 9
                        font.letterSpacing: 1.2
                        Behavior on color { ColorAnimation { duration: Theme.animFast } }
                    }
                    Row {
                        spacing: 4
                        Text {
                            id: num
                            property real shown: tile.mbps
                            Behavior on shown { NumberAnimation { duration: 450; easing.type: Easing.OutCubic } }
                            text: tile.mbps > 0 || tile.live ? Math.round(shown) : "--"
                            color: Theme.fg0
                            font.family: Theme.fontMono
                            font.pixelSize: 18
                            font.weight: Font.DemiBold
                            opacity: tile.live ? 0.75 + 0.25 * pulse.v : 1
                        }
                        Text {
                            anchors.baseline: num.baseline
                            text: "Mbps"
                            color: Theme.fg2
                            font.family: Theme.fontSans
                            font.pixelSize: 10
                        }
                    }
                    Rectangle {
                        width: parent.width; height: 3; radius: 1.5
                        color: Qt.rgba(1, 1, 1, 0.08)
                        Rectangle {
                            width: parent.width * Math.min(1, tile.mbps / tile.scaleTop)
                            height: parent.height; radius: 1.5
                            color: Theme.accent
                            Behavior on width { NumberAnimation { duration: 450; easing.type: Easing.OutCubic } }
                        }
                    }
                }
            }
        }
    }
    // Breathing value while a phase measures.
    QtObject {
        id: pulse
        property real v: 0
        property SequentialAnimation anim: SequentialAnimation {
            running: p.speed.running && p.open
            loops: Animation.Infinite
            NumberAnimation { target: pulse; property: "v"; from: 0; to: 1; duration: 700; easing.type: Easing.InOutSine }
            NumberAnimation { target: pulse; property: "v"; from: 1; to: 0; duration: 700; easing.type: Easing.InOutSine }
        }
    }
    Text {
        width: parent.width
        visible: p.speed.downFrom !== "" && p.speed.phase !== "error"
        text: "Download via " + p.speed.downFrom + (p.speed.upFrom !== "" ? " · upload via " + p.speed.upFrom : "")
        color: Theme.fg3
        font.family: Theme.fontSans
        font.pixelSize: 9
        wrapMode: Text.Wrap
    }
    Text {
        width: parent.width
        visible: p.speed.phase === "error"
        text: "Speed test: " + p.speed.error
        color: Theme.danger
        font.family: Theme.fontSans
        font.pixelSize: 10
        wrapMode: Text.Wrap
    }

    // ---- DNS provider ---------------------------------------------------------
    SectionLabel { text: "DNS"; value: p.dns.busy !== "" ? "applying…" : p.dns.provider }
    Row {
        width: parent.width
        spacing: 4
        Repeater {
            model: p.dns.providers
            Rectangle {
                required property var modelData
                readonly property bool on: p.dns.provider === modelData
                width: (parent.width - 12) / 4; height: 26; radius: 13
                color: on ? Theme.selectFill : (dh.hovered ? Theme.hoverFill : Qt.rgba(1, 1, 1, 0.04))
                border.width: on ? 1 : 0
                border.color: Theme.panelEdge
                Behavior on color { ColorAnimation { duration: Theme.animFast } }
                scale: dt.pressed ? 0.94 : 1
                Behavior on scale { NumberAnimation { duration: Theme.animFast } }
                Text {
                    anchors.centerIn: parent
                    text: modelData
                    color: parent.on ? Theme.fg0 : Theme.fg1
                    font.family: Theme.fontSans
                    font.pixelSize: 10
                }
                HoverHandler { id: dh; cursorShape: Qt.PointingHandCursor }
                TapHandler { id: dt; onTapped: p.dns.choose(modelData) }
            }
        }
    }
    Text {
        width: parent.width
        text: p.dns.provider === "DHCP" && p.net.primaryType === "wifi"
              ? "On Wi-Fi iwd keeps the network's DNS to itself, so DHCP uses the router (" + p.net.gateway + ")."
              : "Custom asks for the servers and your password in a terminal."
        color: Theme.fg3
        font.family: Theme.fontSans
        font.pixelSize: 9
        wrapMode: Text.Wrap
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
