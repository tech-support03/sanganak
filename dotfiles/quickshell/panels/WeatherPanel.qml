// Weather: now, the next hours, three days, and the location (blank = auto
// by IP). Typing a city and pressing Enter saves it for the whole shell.
import QtQuick
import "../theme"
import "../ui"
import "../services" as Services

Panel {
    id: p
    panelId: "weather"
    readonly property var w: Services.Weather
    title: w.city
    subtitle: w.condition
    glyph: w.glyph
    onOpenChanged: if (open) w.refresh()

    Row {
        spacing: 14
        Text {
            text: p.w.tempF + "°"
            color: Theme.fg0
            font.family: Theme.fontMono
            font.pixelSize: 40
            font.weight: Font.Light
        }
        Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 3
            Repeater {
                model: ["Feels " + p.w.feelsF + "°", "Humidity " + p.w.humidity + "%", "Wind " + p.w.windMph + " mph",
                        p.w.sunrise ? "☀ " + p.w.sunrise + " · " + p.w.sunset : ""]
                Text { required property var modelData; visible: modelData !== ""; text: modelData; color: Theme.fg1; font.family: Theme.fontSans; font.pixelSize: 11 }
            }
        }
    }

    SectionLabel { text: "Next hours"; visible: p.w.hours.length > 0 }
    Row {
        width: parent.width
        Repeater {
            model: p.w.hours.slice(0, 6)
            Column {
                required property var modelData
                width: parent.width / 6
                spacing: 3
                Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.time; color: Theme.fg2; font.family: Theme.fontSans; font.pixelSize: 9 }
                Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.glyph; color: Theme.fg0; font.family: Theme.fontMono; font.pixelSize: 16 }
                Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.tempF + "°"; color: Theme.fg0; font.family: Theme.fontMono; font.pixelSize: 11 }
                Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.rainPct + "%"; color: modelData.rainPct >= 40 ? Theme.cyan : Theme.fg3; font.family: Theme.fontMono; font.pixelSize: 9 }
            }
        }
    }

    SectionLabel { text: "Forecast"; visible: p.w.days.length > 0 }
    Repeater {
        model: p.w.days
        Item {
            required property var modelData
            width: parent.width; height: 26
            Text { width: 60; anchors.verticalCenter: parent.verticalCenter; text: modelData.label; color: Theme.fg0; font.family: Theme.fontSans; font.pixelSize: 12 }
            Text { x: 66; anchors.verticalCenter: parent.verticalCenter; text: modelData.glyph; color: Theme.fg0; font.family: Theme.fontMono; font.pixelSize: 15 }
            Text { x: 100; anchors.verticalCenter: parent.verticalCenter; text: modelData.rainPct + "%"; color: modelData.rainPct >= 40 ? Theme.cyan : Theme.fg3; font.family: Theme.fontMono; font.pixelSize: 10 }
            Text { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                   text: modelData.loF + "° / " + modelData.hiF + "°"; color: Theme.fg1; font.family: Theme.fontMono; font.pixelSize: 11 }
        }
    }

    SectionLabel { text: "Location" }
    TextBox {
        placeholder: p.w.location === "" ? "Automatic (by IP) — type a city" : p.w.location
        onAccepted: function (t) { p.w.setLocation(t); text = "" }
    }
    Text {
        visible: p.w.failed
        text: "Couldn't reach wttr.in."
        color: Theme.danger
        font.family: Theme.fontSans
        font.pixelSize: 10
    }
}
