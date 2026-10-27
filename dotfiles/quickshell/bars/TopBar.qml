import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Mpris
import "../theme"
import "../services" as Services

// bars/TopBar.qml — the media notch.
//
// Caelestia-style top bar: invisible at rest, a wide top-center hover target
// expands into a black media notch (art, source, controls, progress). While media plays it shows a waveform that
// floats with no background, and expands the card on hover.
Item {
    id: root

    // ---- active MPRIS player ------------------------------------------------
    // Pick the player that's actually relevant: Playing > Paused > Stopped.
    // Within a tier, prefer one with track metadata, and de-rank Chromium
    // because its MPRIS lingers in "Stopped" state long after any audio is
    // gone and steals priority from Spotify / other real players.
    readonly property var players: Mpris.players ? Mpris.players.values : []
    readonly property var player: {
        const ps = players
        if (!ps || ps.length === 0) return null
        let best = null
        let bestScore = -1
        for (let i = 0; i < ps.length; i++) {
            const p = ps[i]
            if (!p) continue
            let score = 0
            if (p.isPlaying) score += 1000
            else if (p.playbackState === MprisPlaybackState.Paused) score += 500
            if (p.trackTitle && p.trackTitle.length > 0) score += 50
            // Penalise chromium-based MPRIS entries — they're noisy
            const id = (p.identity || "") + " " + (p.dbusName || "")
            if (/chrom(e|ium)/i.test(id)) score -= 200
            if (score > bestScore) { best = p; bestScore = score }
        }
        return best
    }

    // Fallback: detect audio playing via PipeWire even when MPRIS isn't exposed
    // (e.g. Chrome casting to Google Home, which skips MPRIS entirely)
    property bool pipeWireAudioActive: false
    Process {
        id: audioCheckProc
        command: ["sh", "-c", "pactl list sink-inputs short 2>/dev/null | grep -q 'RUNNING' && echo 1 || echo 0"]
        stdout: StdioCollector {
            onStreamFinished: root.pipeWireAudioActive = (this.text.trim() === "1")
        }
    }
    Timer {
        interval: 2000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: audioCheckProc.running = true
    }

    readonly property bool mediaActive: (player !== null && player.isPlaying) || root.pipeWireAudioActive

    // Bring the playing app forward: MPRIS raise() first (browsers use it to
    // switch to the playing tab), then focus its window in case the app
    // ignores raise (Spotify on Linux often does).
    function raisePlayer() {
        const p = root.player
        if (!p) return
        if (p.canRaise) p.raise()
        const names = [p.desktopEntry || "", p.identity || ""].filter(n => n.length > 0)
        if (names.length > 0) { raiseTimer.names = names; raiseTimer.restart() }
    }

    Timer { id: raiseTimer; interval: 150; property var names: []; onTriggered: Services.Niri.focusApp(names) }

    // Track position for the progress line; MPRIS only pushes it on seeks.
    Timer {
        interval: 1000
        repeat: true
        running: root.player !== null && root.player.isPlaying
        onTriggered: if (root.player) root.player.positionChanged()
    }

    // ---- cava waveform (only runs while media is playing) -------------------
    // Skipped entirely in the light profile: spawning cava + driving a 30fps
    // animated bar set is the single most expensive idle cost on Intel HD 5000,
    // and it's pure eye-candy. The rest of the top-bar dashboard is unaffected.
    property var bars: []
    Process {
        id: cavaProc
        running: root.mediaActive && !Services.Profile.light
        command: ["sh", "-c", "command -v cava >/dev/null && exec cava -p " + Qt.resolvedUrl("../cava.conf").toString().replace("file://", "")]
        stdout: SplitParser {
            onRead: line => {
                const parts = line.split(";").filter(s => s.length > 0).map(s => parseInt(s, 10))
                if (parts.length > 0)
                    root.bars = parts
            }
        }
    }

    // When Spotify Connect streams to Chromecast/Google Home, audio never
    // passes through PipeWire so cava gets silence. Fall back to a simulated
    // waveform driven by layered sine waves so the bar animation still plays.
    readonly property bool cavaHasSignal: {
        const b = root.bars
        if (!b || b.length === 0) return false
        let sum = 0
        for (let i = 0; i < b.length; i++) sum += b[i]
        return sum > 20
    }
    property var simBars: []
    property real simT: 0
    Timer {
        interval: 33  // ~30 fps
        repeat: true
        running: root.mediaActive && !root.cavaHasSignal && !Services.Profile.light
        onTriggered: {
            root.simT += 0.033
            const t = root.simT
            const count = 44
            const out = []
            for (let i = 0; i < count; i++) {
                const x = i / (count - 1)
                // Bell-curve envelope so edges are quieter like real music
                const env = Math.exp(-Math.pow((x - 0.5) * 3.2, 2))
                // Three sine layers at coprime frequencies for organic motion
                const v = 0.45 * Math.sin(t * 2.3 + x * 9.1)
                          + 0.35 * Math.sin(t * 3.9 + x * 4.7)
                          + 0.20 * Math.sin(t * 6.1 + x * 14.3)
                const norm = (v + 1) / 2   // [0,1]
                out.push(Math.round(norm * env * 1000))
            }
            root.simBars = out
        }
    }
    readonly property var displayBars: root.cavaHasSignal ? root.bars : root.simBars

    // ---- one panel per monitor ---------------------------------------------
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win
            required property var modelData
            screen: modelData

            anchors { top: true; left: true; right: true }
            exclusiveZone: 0
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            implicitHeight: 380
            WlrLayershell.namespace: "sanganak-topbar"
            WlrLayershell.layer: WlrLayer.Top

            // 0 = hidden, 1 = floating waveform, 2 = expanded dashboard
            // Light profile has no floating-waveform state (mode 1) — the bar is
            // simply hidden at rest and still expands to the full dashboard (mode
            // 2) on hover, so nothing is lost but the animated waveform strip.
            readonly property int mode: (hover.hovered || cardHover.hovered)
                                        ? 2 : ((root.mediaActive && !Services.Profile.light) ? 1 : 0)

            readonly property real cardW: mode === 2 ? 460
                                        : mode === 1 ? wave.implicitWidth + 48
                                        : 520
            readonly property real cardH: mode === 2 ? 132
                                        : mode === 1 ? 44
                                        : 14

            mask: Region { item: hitbox }

            Item {
                id: hitbox
                anchors.horizontalCenter: parent.horizontalCenter
                y: 0
                // Kept deliberately tight: this region is the window's input
                // mask, so every pixel of it eats clicks meant for the app
                // underneath. At rest it is a thin strip at the very top edge,
                // which the pointer still reaches by slamming into the edge.
                width: win.mode === 2 ? win.cardW + 80
                     : win.mode === 1 ? win.cardW + 40
                     : 320
                height: win.mode === 2 ? win.cardH + 40
                      : win.mode === 1 ? win.cardH + 16
                      : 6
                HoverHandler { id: hover }
            }

            // ---- the notch ---------------------------------------------------
            // Opened, the dashboard is a solid black notch hanging from the top
            // edge, like a MacBook notch / Dynamic Island: the top corners flare
            // OUT into the screen edge with concave curves, the bottom corners
            // round in. Drawn as one vector path behind the card so it tracks
            // the card's open/close animation exactly.
            Shape {
                id: notch
                readonly property real flare: Theme.screenRadius       // concave top-corner radius
                readonly property real round: 26       // convex bottom-corner radius
                x: card.x - flare
                y: 0
                width: card.width + flare * 2
                height: card.height
                opacity: win.mode === 2 ? 1 : 0
                visible: opacity > 0
                preferredRendererType: Shape.CurveRenderer
                Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutQuad } }

                ShapePath {
                    fillColor: Theme.bezel
                    strokeWidth: -1
                    startX: 0; startY: 0
                    // top-left flare: concave, curving from the screen edge into the side
                    PathArc { x: notch.flare; y: notch.flare; radiusX: notch.flare; radiusY: notch.flare; direction: PathArc.Clockwise }
                    PathLine { x: notch.flare; y: notch.height - notch.round }
                    // bottom-left: convex round
                    PathArc { x: notch.flare + notch.round; y: notch.height; radiusX: notch.round; radiusY: notch.round; direction: PathArc.Counterclockwise }
                    PathLine { x: notch.width - notch.flare - notch.round; y: notch.height }
                    // bottom-right: convex round
                    PathArc { x: notch.width - notch.flare; y: notch.height - notch.round; radiusX: notch.round; radiusY: notch.round; direction: PathArc.Counterclockwise }
                    PathLine { x: notch.width - notch.flare; y: notch.flare }
                    // top-right flare: concave, back out to the screen edge
                    PathArc { x: notch.width; y: 0; radiusX: notch.flare; radiusY: notch.flare; direction: PathArc.Clockwise }
                    PathLine { x: 0; y: 0 }
                }
            }

            // ---- the visible card (content holder; the notch paints it) ------
            Rectangle {
                id: card
                anchors.horizontalCenter: parent.horizontalCenter
                y: 0

                width: win.cardW
                height: win.cardH
                opacity: win.mode === 0 ? 0 : 1
                clip: true

                // The notch shape behind supplies the black; waveform mode floats.
                color: "transparent"

                Behavior on width   { NumberAnimation { duration: 340; easing.type: Easing.OutExpo } }
                Behavior on height  { NumberAnimation { duration: 340; easing.type: Easing.OutExpo } }
                Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutQuad } }

                // Keeps bar expanded while cursor is anywhere on the card
                HoverHandler { id: cardHover }

                // ---- waveform (mode 1 — floating, no background) ------------
                Waveform {
                    id: wave
                    anchors.centerIn: parent
                    bars: root.displayBars
                    opacity: win.mode === 1 ? 1 : 0
                    visible: opacity > 0
                    Behavior on opacity { NumberAnimation { duration: 160 } }
                }

                // ---- media (mode 2) -------------------------------------------
                Item {
                    id: media
                    anchors.fill: parent
                    anchors.leftMargin: 26
                    anchors.rightMargin: 26
                    anchors.topMargin: 16
                    anchors.bottomMargin: 18
                    opacity: win.mode === 2 ? 1 : 0
                    visible: opacity > 0
                    Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutQuad } }

                    readonly property var p: root.player
                    readonly property real progress: p && p.length > 0 ? Math.min(1, p.position / p.length) : 0

                    // Source: art + text. Clicking it brings the playing app/tab forward.
                    Item {
                        id: source
                        anchors.left: parent.left
                        anchors.right: controls.left
                        anchors.rightMargin: 18
                        anchors.top: parent.top
                        height: 72

                        HoverHandler { id: sourceHover; cursorShape: media.p ? Qt.PointingHandCursor : Qt.ArrowCursor }
                        TapHandler { onTapped: root.raisePlayer() }

                        Rectangle {
                            id: artBox
                            width: 72; height: 72
                            radius: 12
                            clip: true
                            color: Theme.surfaceTint
                            scale: sourceHover.hovered && media.p ? 1.04 : 1.0
                            Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }

                            Image {
                                id: artImg
                                anchors.fill: parent
                                source: media.p ? media.p.trackArtUrl : ""
                                fillMode: Image.PreserveAspectCrop
                            }
                            Text {
                                anchors.centerIn: parent
                                text: "♪"
                                color: Theme.accentDim
                                font.pixelSize: 28
                                visible: artImg.status !== Image.Ready
                            }
                        }

                        Column {
                            anchors.left: artBox.right
                            anchors.leftMargin: 14
                            anchors.right: parent.right
                            anchors.verticalCenter: artBox.verticalCenter
                            spacing: 3

                            Text {
                                width: parent.width
                                visible: !!media.p
                                text: media.p ? (media.p.identity || "").toUpperCase() + (sourceHover.hovered ? "  ↗" : "") : ""
                                color: sourceHover.hovered ? Theme.accentBright : Theme.fg3
                                font.family: Theme.fontSans
                                font.pixelSize: 9
                                font.weight: Font.Medium
                                font.letterSpacing: 1.6
                                elide: Text.ElideRight
                                Behavior on color { ColorAnimation { duration: 160 } }
                            }
                            Text {
                                width: parent.width
                                text: media.p ? (media.p.trackTitle || "Unknown track") : "Nothing playing"
                                color: Theme.blueBright
                                font.family: Theme.fontSans
                                font.pixelSize: 14
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                            }
                            Text {
                                width: parent.width
                                visible: !!(media.p && media.p.trackArtist)
                                text: media.p ? (media.p.trackArtist || "") : ""
                                color: Theme.fg2
                                font.family: Theme.fontSans
                                font.pixelSize: 11
                                elide: Text.ElideRight
                            }
                        }
                    }

                    // Transport controls.
                    Row {
                        id: controls
                        anchors.right: parent.right
                        anchors.verticalCenter: source.verticalCenter
                        spacing: 6
                        visible: !!media.p

                        component Ctl: Rectangle {
                            id: ctl
                            property string glyph: ""
                            property bool big: false
                            signal activated()
                            width: big ? 44 : 34
                            height: width
                            radius: width / 2
                            color: big ? Qt.rgba(1, 1, 1, ctlHover.hovered ? 0.16 : 0.10)
                                       : Qt.rgba(1, 1, 1, ctlHover.hovered ? 0.08 : 0)
                            scale: ctlTap.pressed ? 0.9 : 1.0
                            anchors.verticalCenter: parent.verticalCenter
                            Behavior on color { ColorAnimation { duration: 160 } }
                            Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }
                            Text {
                                anchors.centerIn: parent
                                text: ctl.glyph
                                color: ctlHover.hovered ? Theme.fg0 : Theme.fg1
                                font.family: Theme.fontMono
                                font.pixelSize: ctl.big ? 18 : 15
                            }
                            HoverHandler { id: ctlHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler { id: ctlTap; onTapped: ctl.activated() }
                        }

                        Ctl { glyph: "\uF048"; onActivated: if (media.p) media.p.previous() }
                        Ctl { big: true; glyph: media.p && media.p.isPlaying ? "\uF04C" : "\uF04B"; onActivated: if (media.p) media.p.togglePlaying() }
                        Ctl { glyph: "\uF051"; onActivated: if (media.p) media.p.next() }
                    }

                    // Track progress.
                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: 4
                        radius: 2
                        color: Qt.rgba(1, 1, 1, 0.10)
                        visible: !!(media.p && media.p.length > 0)
                        Rectangle {
                            width: parent.width * media.progress
                            height: parent.height
                            radius: 2
                            color: Theme.accent
                            Behavior on width { NumberAnimation { duration: 900; easing.type: Easing.Linear } }
                        }
                    }
                }
            }
        }
    }
}
