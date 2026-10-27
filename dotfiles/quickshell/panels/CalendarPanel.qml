// Calendar: big 12-hour time, the date, and a month grid with ISO week
// numbers. Arrows / wheel step months; clicking the title returns to today.
import QtQuick
import Quickshell
import "../theme"
import "../ui"

Panel {
    id: p
    panelId: "calendar"
    cardWidth: 300

    SystemClock { id: clock; precision: SystemClock.Seconds }
    property int viewYear: clock.date.getFullYear()
    property int viewMonth: clock.date.getMonth()
    onOpenChanged: if (open) { viewYear = clock.date.getFullYear(); viewMonth = clock.date.getMonth() }

    function step(d) {
        var m = viewMonth + d
        viewYear += Math.floor(m / 12)
        viewMonth = ((m % 12) + 12) % 12
    }
    function isoWeek(y, m, d) {
        var t = new Date(Date.UTC(y, m, d))
        var day = t.getUTCDay() || 7
        t.setUTCDate(t.getUTCDate() + 4 - day)
        var y0 = new Date(Date.UTC(t.getUTCFullYear(), 0, 1))
        return Math.ceil(((t - y0) / 86400000 + 1) / 7)
    }
    // Monday-first grid: 6 rows × 7, each { d, inMonth, today }.
    readonly property var cells: {
        var first = new Date(viewYear, viewMonth, 1)
        var lead = (first.getDay() + 6) % 7
        var out = []
        for (var i = 0; i < 42; i++) {
            var dt = new Date(viewYear, viewMonth, 1 - lead + i)
            out.push({ d: dt.getDate(), m: dt.getMonth(), y: dt.getFullYear(),
                       inMonth: dt.getMonth() === viewMonth,
                       today: dt.toDateString() === clock.date.toDateString() })
        }
        return out
    }

    Column {
        width: parent.width
        spacing: 2
        Text {
            text: Qt.formatDateTime(clock.date, "h:mm AP").split(" ")[0]
            color: Theme.fg0
            font.family: Theme.fontMono
            font.pixelSize: 34
            font.weight: Font.Light
            Text {
                anchors.left: parent.right
                anchors.leftMargin: 6
                anchors.baseline: parent.baseline
                text: Qt.formatDateTime(clock.date, "AP")
                color: Theme.fg2
                font.family: Theme.fontMono
                font.pixelSize: 13
            }
        }
        Text {
            text: Qt.formatDateTime(clock.date, "dddd, d MMMM yyyy")
            color: Theme.accentBright
            font.family: Theme.fontSans
            font.pixelSize: 12
        }
    }

    Item {
        width: parent.width; height: 26
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: Qt.formatDate(new Date(p.viewYear, p.viewMonth, 1), "MMMM yyyy")
            color: Theme.fg0
            font.family: Theme.fontSans
            font.pixelSize: 13
            font.weight: Font.DemiBold
            TapHandler { onTapped: { p.viewYear = clock.date.getFullYear(); p.viewMonth = clock.date.getMonth() } }
        }
        Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4
            Repeater {
                model: [{ g: "", d: -1 }, { g: "", d: 1 }]
                Rectangle {
                    required property var modelData
                    width: 24; height: 24; radius: 12
                    color: h.hovered ? Theme.hoverFill : "transparent"
                    Behavior on color { ColorAnimation { duration: Theme.animFast } }
                    Text { anchors.centerIn: parent; text: modelData.g; color: Theme.fg1; font.family: Theme.fontMono; font.pixelSize: 10 }
                    HoverHandler { id: h; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: p.step(modelData.d) }
                }
            }
        }
    }

    Grid {
        id: grid
        columns: 8
        spacing: 2
        readonly property real cell: (parent.width - 7 * spacing) / 8
        Repeater {
            model: ["W", "M", "T", "W", "T", "F", "S", "S"]
            Text {
                required property var modelData
                required property int index
                width: grid.cell; height: 18
                horizontalAlignment: Text.AlignHCenter
                text: modelData
                color: index === 0 ? Theme.fg3 : Theme.fg2
                font.family: Theme.fontSans
                font.pixelSize: 9
            }
        }
        Repeater {
            model: 48
            Item {
                required property int index
                readonly property int row: Math.floor(index / 8)
                readonly property int col: index % 8
                readonly property var c: col === 0 ? p.cells[row * 7] : p.cells[row * 7 + col - 1]
                width: grid.cell; height: 26
                Rectangle {
                    anchors.centerIn: parent
                    width: 26; height: 26; radius: 6
                    visible: col !== 0
                    color: c.today ? Theme.accent : (h2.hovered ? Theme.hoverFill : "transparent")
                    Behavior on color { ColorAnimation { duration: Theme.animFast } }
                    HoverHandler { id: h2 }
                }
                Text {
                    anchors.centerIn: parent
                    text: col === 0 ? p.isoWeek(c.y, c.m, c.d) : c.d
                    color: col === 0 ? Theme.fg3 : (c.today ? Theme.base : (c.inMonth ? Theme.fg0 : Theme.fg3))
                    font.family: Theme.fontMono
                    font.pixelSize: col === 0 ? 9 : 11
                    font.weight: c.today ? Font.Bold : Font.Normal
                }
            }
        }
        WheelHandler { onWheel: function (ev) { p.step(ev.angleDelta.y > 0 ? -1 : 1) } }
    }
}
