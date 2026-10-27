// AI coding agents: plan, limits with reset countdowns, tokens by day and by
// model. One chip per agent when there is more than one. Data comes from
// services/Agents.qml (sanganak-agent-usage records).
import QtQuick
import Quickshell
import "../theme"
import "../ui"
import "../services" as Services

Panel {
    id: p
    panelId: "agents"
    readonly property var list: Services.Agents.agents
    property int sel: 0
    readonly property var a: list.length > 0 ? list[Math.min(sel, list.length - 1)] : null
    title: a ? a.name : "Agents"
    subtitle: a ? (a.authError || (a.plan ? a.plan + " plan" : "")) : ""
    glyph: "󰚩"
    onOpenChanged: if (open) Services.Agents.refresh()

    SystemClock { id: clock; precision: SystemClock.Minutes }
    function fmtTokens(n) {
        if (n >= 1e9) return (n / 1e9).toFixed(1) + "B"
        if (n >= 1e6) return (n / 1e6).toFixed(1) + "M"
        if (n >= 1e3) return Math.round(n / 1e3) + "K"
        return String(n)
    }
    function resetIn(iso) {
        if (!iso) return ""
        var ms = new Date(iso) - clock.date
        if (isNaN(ms) || ms <= 0) return "resetting"
        var h = Math.floor(ms / 3600000), d = Math.floor(h / 24)
        return "resets in " + (d > 0 ? d + "d " + (h % 24) + "h" : h + "h " + Math.floor(ms % 3600000 / 60000) + "m")
    }

    Row {
        visible: p.list.length > 1
        spacing: 6
        Repeater {
            model: p.list
            Rectangle {
                required property var modelData
                required property int index
                width: chipText.implicitWidth + 24; height: 24; radius: 12
                color: index === p.sel ? Theme.selectFill : (h.hovered ? Theme.hoverFill : Qt.rgba(1, 1, 1, 0.04))
                Behavior on color { ColorAnimation { duration: Theme.animFast } }
                Text { id: chipText; anchors.centerIn: parent; text: modelData.name; color: Theme.fg0; font.family: Theme.fontSans; font.pixelSize: 11 }
                HoverHandler { id: h; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: p.sel = index }
            }
        }
    }

    Repeater {
        model: p.a ? p.a.limits : []
        Column {
            required property var modelData
            width: parent.width
            spacing: 5
            SectionLabel { text: modelData.label; value: Math.round(modelData.percent * 100) + "%" }
            Rectangle {
                width: parent.width; height: 6; radius: 3
                color: Qt.rgba(1, 1, 1, 0.08)
                Rectangle {
                    width: parent.width * modelData.percent; height: 6; radius: 3
                    color: modelData.percent >= 0.9 ? Theme.danger : modelData.percent >= 0.7 ? Theme.accentBright : Theme.accent
                    Behavior on width { NumberAnimation { duration: Theme.animMed } }
                }
            }
            Text { text: p.resetIn(modelData.resetsAt); color: Theme.fg2; font.family: Theme.fontSans; font.pixelSize: 10 }
        }
    }

    SectionLabel { text: "Tokens by day"; value: p.a ? "today " + p.fmtTokens(p.a.todayTokens) : "" }
    Repeater {
        model: p.a ? p.a.days : []
        Item {
            required property var modelData
            required property int index
            readonly property real peak: Math.max.apply(null, p.a.days.map(function (d) { return d.tokens }).concat([1]))
            readonly property bool today: index === p.a.days.length - 1
            width: parent.width; height: 16
            Text { width: 34; text: Qt.formatDate(new Date(modelData.date + "T12:00:00"), "ddd"); color: today ? Theme.fg0 : Theme.fg2
                   font.family: Theme.fontSans; font.pixelSize: 10; font.weight: today ? Font.Bold : Font.Normal }
            Rectangle {
                x: 38; anchors.verticalCenter: parent.verticalCenter
                width: (parent.width - 38 - 50) * modelData.tokens / parent.peak; height: 6; radius: 3
                color: today ? Theme.accent : Theme.tint(Theme.accent, 0.5)
                Behavior on width { NumberAnimation { duration: Theme.animMed } }
            }
            Text { anchors.right: parent.right; text: p.fmtTokens(modelData.tokens); color: Theme.fg1; font.family: Theme.fontMono; font.pixelSize: 10 }
        }
    }

    SectionLabel { text: "Tokens by model (7 days)"; visible: !!p.a }
    Repeater {
        model: p.a ? Object.keys(p.a.models).map(function (k) {
            var m = p.a.models[k]; return { name: k, total: m.input + m.output + m.cacheRead + m.cacheWrite, m: m }
        }).sort(function (x, y) { return y.total - x.total }) : []
        ListRow {
            required property var modelData
            label: modelData.name
            detail: p.fmtTokens(modelData.total)
            glyph: "󰘦"
        }
    }
    ListRow {
        glyph: "󰑐"
        label: Services.Agents.refreshing ? "Refreshing…" : "Refresh"
        onClicked: Services.Agents.refresh()
    }
}
