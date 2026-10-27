// AI coding agent usage. Hidden until a usage record exists.
import QtQuick
import "../../theme"
import "../../ui"
import "../../services" as Services

BarButton {
    panelId: "agents"
    visible: Services.Agents.agents.length > 0
    glyph: "󰚩"
    tint: Services.Agents.hottest >= 0.9 ? Theme.danger : Theme.fg0
}
