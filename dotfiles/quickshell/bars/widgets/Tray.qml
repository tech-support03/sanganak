// StatusNotifier tray. Left click activates, right click opens the app's menu.
// Two instances split the icons: mode "services" (inside TrayDrawer, revealed
// on hover) holds every tray icon — Discord, wooting-bg-service, … — and mode
// "apps" (in the system section) shows an icon only while it asks for
// attention (SNI status NeedsAttention), so nothing urgent stays hidden.
// Icons are drawn through a Canvas that repaints dark single-colour icons in
// the bar's white and Discord's baked-in red unread dot in the theme accent;
// `badges` counts icons showing such a dot, for the drawer handle.
import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import "../../theme"

Column {
    id: tray
    property string mode: "apps"
    // Menus open from this column; TrayDrawer stays open while one is.
    property int openMenus: 0
    property int badges: 0
    readonly property int count: SystemTray.items.values.filter(function (it) { return tray.accepts(it) }).length
    visible: count > 0
    spacing: 2

    function accepts(item) { return (item.status === Status.NeedsAttention) === (mode === "apps") }
    // Some apps (wooting-bg-service and other tray-icon crate users) report a
    // file path as IconName; Quickshell wraps it as image://icon/<path>?path=…,
    // which the icon-theme lookup can't resolve. Load the file directly.
    function iconSource(icon) {
        var m = (icon || "").match(/^image:\/\/icon\/(\/[^?]+)/)
        return m ? "file://" + m[1] : icon
    }

    Repeater {
        model: SystemTray.items
        delegate: Item {
            id: slot
            required property var modelData
            readonly property bool recolor: /discord|vesktop|webcord|legcord|armcord/i
                                            .test((modelData.id || "") + " " + (modelData.title || ""))
            visible: tray.accepts(modelData)
            // Shows an unread dot (Discord's red one); feeds tray.badges.
            property bool badged: false
            onBadgedChanged: tray.badges = Math.max(0, tray.badges + (badged ? 1 : -1))
            Component.onDestruction: if (badged) tray.badges = Math.max(0, tray.badges - 1)
            width: Theme.barSize
            height: 28
            Rectangle {
                anchors.centerIn: parent
                width: 30; height: 26; radius: Theme.radiusSmall
                color: hov.hovered ? Qt.rgba(1, 1, 1, 0.09) : "transparent"
                Behavior on color { ColorAnimation { duration: Theme.animFast } }
            }
            // Every icon goes through this Canvas, which fixes two kinds of icon
            // for the black bar: a dark single-colour icon (wooting-bg-service
            // ships a black one for light panels) is repainted in the bar's
            // white, and Discord's red unread dot is shifted to the accent.
            Canvas {
                id: icon
                anchors.centerIn: parent
                width: 16; height: 16
                scale: tap.pressed ? 0.85 : 1
                Behavior on scale { NumberAnimation { duration: Theme.animFast } }
                // The URL changes whenever the app swaps its icon; drop the old
                // image so the cache doesn't grow with each swap.
                readonly property string src: tray.iconSource(slot.modelData.icon)
                property string held: ""
                readonly property color accent: Theme.accent
                readonly property color ink: Theme.fg0
                function load() {
                    if (held !== "" && held !== src) unloadImage(held)
                    held = src
                    if (src !== "") { if (isImageLoaded(src)) requestPaint(); else loadImage(src) }
                }
                Component.onCompleted: load()
                onSrcChanged: load()
                onAccentChanged: requestPaint()
                onImageLoaded: requestPaint()
                onPaint: {
                    var ctx = getContext("2d")
                    ctx.clearRect(0, 0, width, height)
                    if (src === "" || !isImageLoaded(src)) return
                    ctx.drawImage(src, 0, 0, width, height)
                    var d = ctx.getImageData(0, 0, width, height).data
                    // Mean luminance of the visible pixels: near black = repaint.
                    var lum = 0, n = 0
                    for (var k = 0; k < d.length; k += 4)
                        if (d[k + 3] > 40) { lum += 0.2126 * d[k] + 0.7152 * d[k + 1] + 0.0722 * d[k + 2]; n++ }
                    var dark = n > 0 && lum / n < 30
                    if (slot.recolor) {
                        var dot = 0
                        for (var q = 0; q < d.length; q += 4)
                            if (d[q + 3] > 128 && d[q] - Math.max(d[q + 1], d[q + 2]) > 100) dot++
                        slot.badged = dot >= 4
                    }
                    if (!dark && !slot.recolor) return
                    // putImageData() doesn't take edited pixels on this Qt, so
                    // the changed ones are repainted one by one.
                    var ar = accent.r * 255, ag = accent.g * 255, ab = accent.b * 255
                    for (var i = 0; i < d.length; i += 4) {
                        if (d[i + 3] === 0) continue
                        var x = (i / 4) % width, y = Math.floor(i / 4 / width)
                        if (dark) {
                            ctx.clearRect(x, y, 1, 1)
                            ctx.fillStyle = Qt.rgba(ink.r, ink.g, ink.b, d[i + 3] / 255)
                            ctx.fillRect(x, y, 1, 1)
                            continue
                        }
                        // Shift each reddish pixel by how red it is, so the dot's
                        // anti-aliased rim blends in too; 169 is the redness of
                        // Discord's #f04747.
                        var red = d[i] - Math.max(d[i + 1], d[i + 2])
                        if (red <= 24) continue
                        var t = Math.min(1, red / 169)
                        ctx.clearRect(x, y, 1, 1)
                        ctx.fillStyle = Qt.rgba(Math.max(0, Math.min(255, d[i] + t * (ar - 240))) / 255,
                                                Math.max(0, Math.min(255, d[i + 1] + t * (ag - 71))) / 255,
                                                Math.max(0, Math.min(255, d[i + 2] + t * (ab - 71))) / 255,
                                                d[i + 3] / 255)
                        ctx.fillRect(x, y, 1, 1)
                    }
                }
            }
            QsMenuAnchor {
                id: menu
                menu: slot.modelData.menu
                anchor.item: slot
                anchor.edges: Edges.Left
                anchor.gravity: Edges.Left
                onVisibleChanged: tray.openMenus = Math.max(0, tray.openMenus + (visible ? 1 : -1))
            }
            HoverHandler { id: hov; cursorShape: Qt.PointingHandCursor }
            TapHandler {
                id: tap
                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                onTapped: function (ev, button) {
                    if (button === Qt.RightButton || slot.modelData.onlyMenu) { if (slot.modelData.hasMenu) menu.open() }
                    else if (button === Qt.MiddleButton) slot.modelData.secondaryActivate()
                    else slot.modelData.activate()
                }
            }
        }
    }
}
