// Output volume. Left: panel. Right: mute. Wheel: volume ±5%.
import QtQuick
import Quickshell.Services.Pipewire
import "../../theme"
import "../../ui"

BarButton {
    id: a
    panelId: "audio"
    readonly property var sink: Pipewire.defaultAudioSink
    PwObjectTracker { objects: [a.sink] }
    readonly property real vol: sink && sink.audio ? sink.audio.volume : 0
    readonly property bool muted: sink && sink.audio ? sink.audio.muted : true
    glyph: muted ? "󰝟" : vol > 0.66 ? "󰕾" : vol > 0.33 ? "󰖀" : "󰕿"
    tint: muted ? Theme.fg3 : Theme.fg0
    onClicked: function (button) { if (button === Qt.RightButton && sink && sink.audio) sink.audio.muted = !sink.audio.muted }
    onWheel: function (delta) {
        if (!sink || !sink.audio) return
        sink.audio.volume = Math.max(0, Math.min(1, sink.audio.volume + (delta > 0 ? 0.05 : -0.05)))
    }
}
