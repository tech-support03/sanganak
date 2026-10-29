// The sanganak menu. Type to filter; Up/Down move; Enter runs. Terminal tools
// (package install / remove, updates, keybindings) open in a floating
// alacritty (`sanganak.float` / `sanganak.update` classes, floated by niri).
import QtQuick
import Quickshell
import "../theme"
import "../ui"
import "../services" as Services

Panel {
    id: p
    panelId: "menu"
    title: "sanganak"
    glyph: "󰣇"
    cardWidth: 320

    function term(cls, cmd) { return ["alacritty", "--class", cls, "-e"].concat(cmd) }
    readonly property var items: [
        { g: "󰀻", l: "Apps", c: ["qs", "ipc", "call", "launcher", "toggle"] },
        { g: "󰏗", l: "Install package", c: term("sanganak.float", ["sanganak-pkg-install"]) },
        { g: "󰣇", l: "Install AUR package", c: term("sanganak.float", ["sanganak-pkg-aur-install"]) },
        { g: "󰆴", l: "Remove package", c: term("sanganak.float", ["sanganak-pkg-remove"]) },
        { g: "󰚰", l: "Update system", c: term("sanganak.update", ["sanganak-update"]) },
        { g: "󰌌", l: "Keybindings", c: ["sanganak-keybindings"] },
        { g: "󰏘", l: "Theme", c: ["qs", "ipc", "call", "theme", "toggle"] },
        { g: "󰸉", l: "Next wallpaper", c: ["wallpaper-next"] },
        { g: "󰡼", l: "Add wallpaper", c: term("sanganak.float", ["wallpaper", "add"]) },
        { g: "󱐘", l: "Remove current wallpaper", c: ["wallpaper", "rm"] },
        { g: "󰉏", l: "Wallpapers folder", c: ["wallpaper", "open"] },
        { g: "󱄄", l: "Screensaver", c: ["sanganak-screensaver"] },
        { g: "󰹑", l: "Screenshot", c: ["niri", "msg", "action", "screenshot"] },
        { g: "󰾆", l: "Toggle full / light profile", c: ["rice-profile", "toggle"] },
        { g: "󰌁", l: "RGB lighting", c: ["qs", "ipc", "call", "rgb", "toggle"] },
        { g: "󰍹", l: "Arrange displays", c: ["nwg-displays"] },
        { g: "󰋼", l: "System info", c: ["fastfetch-popup"] },
        { g: "󰒓", l: "Finish setup (re-run)", c: term("sanganak.update", ["sanganak-finish-setup", "--force"]) },
        { g: "", l: "Power", c: ["qs", "ipc", "call", "power", "toggle"] }
    ]
    property string query: ""
    property int sel: 0
    readonly property var shown: items.filter(function (it) { return it.l.toLowerCase().indexOf(query.toLowerCase()) !== -1 })
    onQueryChanged: sel = 0
    onOpenChanged: if (open) { search.text = ""; sel = 0; Qt.callLater(function () { search.input.forceActiveFocus() }) }

    function run(it) {
        if (!it) return
        Services.Panels.close()
        Quickshell.execDetached(it.c)
    }

    TextBox {
        id: search
        placeholder: "Search…"
        onTextChanged: p.query = text
        onAccepted: p.run(p.shown[p.sel])
        input.Keys.onDownPressed: p.sel = Math.min(p.shown.length - 1, p.sel + 1)
        input.Keys.onUpPressed: p.sel = Math.max(0, p.sel - 1)
        input.Keys.onEscapePressed: Services.Panels.close()
    }
    Repeater {
        model: p.shown
        ListRow {
            required property var modelData
            required property int index
            glyph: modelData.g
            label: modelData.l
            active: index === p.sel
            onClicked: p.run(modelData)
        }
    }
}
