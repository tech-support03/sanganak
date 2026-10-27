// services/Niri.qml — live niri state over its JSON event stream.
//
// `niri msg --json event-stream` sends the full workspace / window / keyboard
// layout state on connect and then incremental events, so one long-lived
// process keeps this singleton current with no polling. Everything in the
// shell that used to ask Hyprland (workspaces, focused window, layouts) reads
// from here; everything that used to dispatch to Hyprland goes through act().
pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: niri

    // [{ id, idx, name, output, is_active, is_focused, active_window_id }]
    property var workspaces: []
    // { id: { id, title, app_id, workspace_id, is_focused } }
    property var windows: ({})
    property var focusedWindowId: null
    property var layoutNames: []
    property int layoutIndex: 0
    property bool overviewOpen: false
    property bool connected: false

    readonly property var focusedWindow: focusedWindowId !== null && windows[focusedWindowId] ? windows[focusedWindowId] : null
    readonly property var focusedWorkspace: {
        for (var i = 0; i < workspaces.length; i++)
            if (workspaces[i].is_focused) return workspaces[i]
        return null
    }
    readonly property string currentLayout: layoutNames.length > layoutIndex ? layoutNames[layoutIndex] : ""

    // Workspaces on one output, in niri's own order (idx).
    function workspacesOn(output) {
        var out = []
        for (var i = 0; i < workspaces.length; i++)
            if (workspaces[i].output === output) out.push(workspaces[i])
        out.sort(function (a, b) { return a.idx - b.idx })
        return out
    }

    function windowCountOn(workspaceId) {
        var n = 0
        for (var k in windows) if (windows[k].workspace_id === workspaceId) n++
        return n
    }

    // `niri msg action <args...>`
    function act(args) { Quickshell.execDetached(["niri", "msg", "action"].concat(args)) }
    function focusWorkspace(ref) { act(["focus-workspace", String(ref)]) }
    // A workspace index is relative to the focused output, so focus the
    // workspace's own output first (one shell, so the two run in order).
    function focusWorkspaceOn(output, idx) {
        Quickshell.execDetached(["sh", "-c", 'niri msg action focus-monitor "$1" && niri msg action focus-workspace "$2"', "sh", output, String(idx)])
    }
    function focusWindow(id) { act(["focus-window", "--id", String(id)]) }
    function switchLayout(which) { act(["switch-layout", which || "next"]) }

    // Bring an app's window forward by app-id or title match (case-insensitive
    // substring). Used by the media notch to raise the playing app.
    function focusApp(names) {
        var wanted = (names || []).map(function (n) { return String(n).toLowerCase() }).filter(function (n) { return n.length > 0 })
        for (var k in windows) {
            var w = windows[k]
            var app = String(w.app_id || "").toLowerCase()
            for (var i = 0; i < wanted.length; i++)
                if (app === wanted[i] || app.indexOf(wanted[i]) !== -1) { focusWindow(w.id); return true }
        }
        return false
    }

    function _setWindow(w) {
        var next = Object.assign({}, windows)
        next[w.id] = w
        if (w.is_focused) focusedWindowId = w.id
        windows = next
    }

    function _handle(ev) {
        if (ev.WorkspacesChanged) {
            workspaces = ev.WorkspacesChanged.workspaces
        } else if (ev.WorkspaceActivated) {
            var a = ev.WorkspaceActivated
            var target = null
            for (var i = 0; i < workspaces.length; i++) if (workspaces[i].id === a.id) target = workspaces[i]
            if (!target) return
            workspaces = workspaces.map(function (w) {
                var c = Object.assign({}, w)
                if (w.output === target.output) c.is_active = (w.id === a.id)
                if (a.focused) c.is_focused = (w.id === a.id)
                return c
            })
        } else if (ev.WorkspaceActiveWindowChanged) {
            var e = ev.WorkspaceActiveWindowChanged
            workspaces = workspaces.map(function (w) {
                if (w.id !== e.workspace_id) return w
                var c = Object.assign({}, w); c.active_window_id = e.active_window_id; return c
            })
        } else if (ev.WindowsChanged) {
            var map = {}
            focusedWindowId = null
            ev.WindowsChanged.windows.forEach(function (w) { map[w.id] = w; if (w.is_focused) focusedWindowId = w.id })
            windows = map
        } else if (ev.WindowOpenedOrChanged) {
            _setWindow(ev.WindowOpenedOrChanged.window)
        } else if (ev.WindowClosed) {
            var rest = Object.assign({}, windows)
            delete rest[ev.WindowClosed.id]
            if (focusedWindowId === ev.WindowClosed.id) focusedWindowId = null
            windows = rest
        } else if (ev.WindowFocusChanged) {
            focusedWindowId = ev.WindowFocusChanged.id
        } else if (ev.KeyboardLayoutsChanged) {
            layoutNames = ev.KeyboardLayoutsChanged.keyboard_layouts.names
            layoutIndex = ev.KeyboardLayoutsChanged.keyboard_layouts.current_idx
        } else if (ev.KeyboardLayoutSwitched) {
            layoutIndex = ev.KeyboardLayoutSwitched.idx
        } else if (ev.OverviewOpenedOrClosed) {
            overviewOpen = ev.OverviewOpenedOrClosed.is_open
        }
    }

    property Process _stream: Process {
        // Outside a niri session (NIRI_SOCKET unset) there is nothing to follow.
        running: !!Quickshell.env("NIRI_SOCKET")
        command: ["niri", "msg", "--json", "event-stream"]
        stdout: SplitParser {
            onRead: function (line) {
                niri.connected = true
                try { niri._handle(JSON.parse(line)) } catch (e) { }
            }
        }
        // niri restarts (or a config reload hiccup) drop the stream; reconnect.
        onExited: { niri.connected = false; niri._retry.restart() }
    }
    property Timer _retry: Timer {
        interval: 1500
        onTriggered: if (Quickshell.env("NIRI_SOCKET")) niri._stream.running = true
    }
}
