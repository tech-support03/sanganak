// Audio: output and input level, device pickers, and a per-app mixer.
// Straight on Quickshell's PipeWire service; the header switch mutes or
// unmutes everything audible.
import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import "../theme"
import "../ui"
import "../services" as Services

Panel {
    id: p
    panelId: "audio"
    title: "Audio"
    glyph: outMuted ? "󰝟" : "󰕾"
    subtitle: sink ? (sink.description || sink.nickname || sink.name) : "No output"

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource
    readonly property var nodes: Pipewire.nodes ? Pipewire.nodes.values : []
    readonly property var sinks: nodes.filter(function (n) { return n && n.isSink && !n.isStream && n.audio })
    readonly property var sources: nodes.filter(function (n) {
        return n && !n.isSink && !n.isStream && n.audio && String(n.name || "").indexOf(".monitor") === -1
    })
    readonly property var streams: nodes.filter(function (n) { return n && n.isStream && n.isSink && n.audio })
    PwObjectTracker { objects: [p.sink, p.source].concat(p.sinks, p.sources, p.streams) }

    readonly property bool outMuted: !sink || !sink.audio || sink.audio.muted
    readonly property bool inMuted: !source || !source.audio || source.audio.muted
    showSwitch: true
    switchOn: !outMuted || !inMuted
    onSwitchToggled: {
        var mute = switchOn
        if (sink && sink.audio) sink.audio.muted = mute
        if (source && source.audio) source.audio.muted = mute
    }

    function nameOf(n) { return n.description || n.nickname || n.name || "Device" }
    function glyphOf(n, input) {
        var s = (nameOf(n) + " " + (n.name || "")).toLowerCase()
        if (/head|ear|buds|airpods|usb-c/.test(s)) return input ? "󰋎" : "󰋋"
        if (/hdmi|displayport|dp/.test(s)) return "󰡁"
        if (/blue|bluez/.test(s)) return "󰂯"
        if (/cam|kiyo|webcam/.test(s)) return "󰄀"
        return input ? "󰍬" : "󰓃"
    }

    SectionLabel { text: "Output"; value: p.sink && p.sink.audio ? Math.round(p.sink.audio.volume * 100) + "%" : "" }
    Slider {
        width: parent.width
        value: p.sink && p.sink.audio ? p.sink.audio.volume : 0
        fill: p.outMuted ? Theme.fg3 : Theme.accent
        onMoved: function (v) { if (p.sink && p.sink.audio) { p.sink.audio.volume = v; if (v > 0) p.sink.audio.muted = false } }
    }
    Repeater {
        model: p.sinks
        ListRow {
            required property var modelData
            glyph: p.glyphOf(modelData, false)
            label: p.nameOf(modelData)
            active: modelData === p.sink
            onClicked: Pipewire.preferredDefaultAudioSink = modelData
        }
    }

    SectionLabel { text: "Input"; value: p.source && p.source.audio ? Math.round(p.source.audio.volume * 100) + "%" : ""; visible: p.sources.length > 0 }
    Slider {
        width: parent.width
        visible: p.sources.length > 0
        value: p.source && p.source.audio ? p.source.audio.volume : 0
        fill: p.inMuted ? Theme.fg3 : Theme.cyan
        onMoved: function (v) { if (p.source && p.source.audio) { p.source.audio.volume = v; if (v > 0) p.source.audio.muted = false } }
    }
    Repeater {
        model: p.sources
        ListRow {
            required property var modelData
            glyph: p.glyphOf(modelData, true)
            label: p.nameOf(modelData)
            active: modelData === p.source
            onClicked: Pipewire.preferredDefaultAudioSource = modelData
        }
    }

    SectionLabel { text: "Apps"; visible: p.streams.length > 0 }
    Repeater {
        model: p.streams
        Column {
            required property var modelData
            width: parent.width
            spacing: 4
            Item {
                width: parent.width; height: 16
                Text {
                    text: (modelData.properties["application.name"] || modelData.description || modelData.name || "App")
                    color: Theme.fg1
                    font.family: Theme.fontSans
                    font.pixelSize: 11
                    elide: Text.ElideRight
                    width: parent.width - 40
                }
                Text {
                    anchors.right: parent.right
                    text: Math.round(modelData.audio.volume * 100) + "%"
                    color: Theme.fg2
                    font.family: Theme.fontMono
                    font.pixelSize: 10
                }
            }
            Slider {
                width: parent.width
                value: modelData.audio.volume
                fill: modelData.audio.muted ? Theme.fg3 : Theme.blue
                onMoved: function (v) { modelData.audio.volume = v }
            }
        }
    }

    ListRow {
        glyph: "󰒓"
        label: "Advanced mixer"
        onClicked: { Quickshell.execDetached(["pavucontrol"]); Services.Panels.close() }
    }
}
