// Pending updates, split repo / AUR, with the update TUI one click away.
import QtQuick
import Quickshell
import "../theme"
import "../ui"
import "../services" as Services

Panel {
    id: p
    panelId: "updates"
    readonly property var u: Services.Updates
    title: u.total + (u.total === 1 ? " update" : " updates")
    subtitle: u.checking ? "checking…" : (u.checkedAt ? "checked " + u.checkedAt : "")
    glyph: ""

    ListRow {
        glyph: "󰚰"
        label: "Update now"
        active: true
        onClicked: { p.u.runUpdate(); Services.Panels.close() }
    }
    SectionLabel { text: "Packages"; value: p.u.aurCount > 0 ? p.u.aurCount + " AUR" : "" }
    Repeater {
        model: p.u.packages.slice(0, 40)
        Item {
            required property var modelData
            width: parent.width; height: 18
            Text { width: parent.width * 0.5; text: modelData.name + (modelData.aur ? "  ·aur" : ""); color: Theme.fg0
                   font.family: Theme.fontMono; font.pixelSize: 10; elide: Text.ElideRight }
            Text { anchors.right: parent.right; width: parent.width * 0.48; horizontalAlignment: Text.AlignRight
                   text: modelData.to; color: Theme.fg2; font.family: Theme.fontMono; font.pixelSize: 10; elide: Text.ElideLeft }
        }
    }
    Text { visible: p.u.total > 40; text: "…and " + (p.u.total - 40) + " more"; color: Theme.fg2; font.family: Theme.fontSans; font.pixelSize: 10 }
    ListRow { glyph: "󰑐"; label: "Check again"; onClicked: p.u.check() }
}
