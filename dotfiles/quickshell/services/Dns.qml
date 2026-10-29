// services/Dns.qml — the DNS provider row of the network panel.
//
// `sanganak-dns` (scripts/sanganak-dns.sh) owns /etc/resolv.conf: run bare it
// names the current provider, and as root it writes one. Cloudflare / Google /
// DHCP go through `sudo -n` (07-services.sh allows exactly those); Custom, and
// any of them when that rule is missing, open a floating terminal where sudo
// can ask for the password. The file is watched, so a change made anywhere
// shows up here. In DHCP mode a new gateway (another network, cable in or out)
// re-runs `DHCP` so the servers follow the network.
pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: dns

    readonly property var providers: ["DHCP", "Cloudflare", "Google", "Custom"]
    property string provider: ""
    property string busy: ""           // provider being applied

    function refresh() { if (!_read.running) _read.running = true }
    function choose(p) {
        if (p === "Custom") { _terminal(["sanganak-dns", "--custom"]); return }
        if (_set.running) return
        busy = p
        _set.wanted = p
        _set.command = ["sudo", "-n", "/usr/local/bin/sanganak-dns", p]
        _set.running = true
    }
    function _terminal(cmd) {
        Quickshell.execDetached(["alacritty", "--class", "sanganak.float", "--title", "DNS", "-e"].concat(cmd))
    }

    property Process _read: Process {
        command: ["sanganak-dns"]
        stdout: StdioCollector { onStreamFinished: dns.provider = text.trim() }
    }
    property Process _set: Process {
        property string wanted: ""
        onExited: function (code) {
            dns.busy = ""
            // No sudoers rule (or it needs a password): let sudo ask in a terminal.
            if (code !== 0 && !dns._quiet) dns._terminal(["sudo", "/usr/local/bin/sanganak-dns", wanted])
            dns._quiet = false
            dns.refresh()
        }
    }
    property bool _quiet: false

    property FileView _watch: FileView {
        path: "/etc/resolv.conf"
        watchChanges: true
        onFileChanged: dns.refresh()
    }

    property Connections _follow: Connections {
        target: Network
        function onGatewayChanged() {
            if (dns.provider !== "DHCP" || Network.gateway === "" || dns._set.running) return
            dns._quiet = true              // automatic: never pop a terminal for this
            dns._set.wanted = "DHCP"
            dns._set.command = ["sudo", "-n", "/usr/local/bin/sanganak-dns", "DHCP"]
            dns._set.running = true
        }
    }

    Component.onCompleted: refresh()
}
