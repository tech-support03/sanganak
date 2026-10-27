// services/Panels.qml — which edge-bar panel is open, and on which screen.
//
// Only one panel is open at a time. The edge bar stays revealed on a screen
// while that screen has a panel open, and a panel opening anywhere closes the
// previous one. Panels and the `qs ipc call panel …` handler both go through
// here, so keyboard binds and bar clicks share one state.
pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: panels

    property string openId: ""
    property string openScreen: ""
    // Where along the bar the anchor widget sits (screen-local y of its
    // centre), so the card opens next to the icon that summoned it.
    property real anchorY: -1

    function isOpen(id) { return openId === id }
    function openOn(screenName) { return openId !== "" && openScreen === screenName }

    function open(id, screenName, y) {
        openScreen = screenName || _focusedOutput()
        anchorY = (y === undefined) ? -1 : y
        openId = id
    }
    function close() { openId = "" }
    function toggle(id, screenName, y) {
        if (openId === id && (!screenName || screenName === openScreen)) close()
        else open(id, screenName, y)
    }

    // A keyboard-summoned panel opens on the focused output.
    function _focusedOutput() {
        var ws = Niri.focusedWorkspace
        if (ws && ws.output) return ws.output
        var s = Quickshell.screens
        return s.length > 0 ? s[0].name : ""
    }

    property IpcHandler _ipc: IpcHandler {
        target: "panel"
        function toggle(id: string): void { panels.toggle(id, "", -1) }
        function open(id: string): void { panels.open(id, "", -1) }
        function close(): void { panels.close() }
    }
}
