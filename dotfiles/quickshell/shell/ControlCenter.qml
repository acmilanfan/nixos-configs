import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Pipewire

PanelWindow {
    id: cc

    property string page: ""
    property var targetScreen: null
    signal closeRequested()

    readonly property color bg: "#1a1b26"
    readonly property color card: "#1f2130"
    readonly property color cardHover: "#272a3d"
    readonly property color border: "#2b3b51"
    readonly property color fg: "#c6d0f5"
    readonly property color dim: "#7f849c"
    readonly property color accent: "#7b5cff"

    visible: page !== ""
    screen: targetScreen
    anchors {
        top: true
        left: page === "quick"
        right: page === "control"
    }
    margins {
        top: 27
        left: 3
        right: 3
    }
    implicitWidth: 360
    implicitHeight: content.implicitHeight + 28
    exclusiveZone: 0
    color: "transparent"
    WlrLayershell.namespace: "quickshell-control-center"

    PwObjectTracker {
        objects: Pipewire.defaultAudioSink ? [Pipewire.defaultAudioSink] : []
    }

    component Tile: Rectangle {
        id: tile
        property string glyph: ""
        property string label: ""
        property string subCommand: ""
        property string command: ""
        property bool active: false

        Layout.fillWidth: true
        implicitHeight: 54
        radius: 8
        color: tile.active ? "#2a2350" : (hover.hovered ? cc.cardHover : cc.card)
        border.width: 1
        border.color: tile.active ? cc.accent : cc.border

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 9
            anchors.rightMargin: 9
            spacing: 8

            Rectangle {
                implicitWidth: 26
                implicitHeight: 26
                radius: 7
                color: Qt.rgba(1, 1, 1, 0.04)

                Text {
                    anchors.centerIn: parent
                    text: tile.glyph
                    color: tile.active ? cc.accent : cc.fg
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 14
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                Text {
                    text: tile.label
                    color: tile.active ? cc.accent : cc.fg
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 10
                    font.bold: true
                }

                ScriptLabel {
                    visible: tile.subCommand !== ""
                    Layout.fillWidth: true
                    command: tile.subCommand
                    interval: 5
                    textColor: cc.dim
                }
            }
        }

        HoverHandler { id: hover }

        MouseArea {
            anchors.fill: parent
            onClicked: {
                if (tile.command)
                    Quickshell.execDetached(["sh", "-c", tile.command])
                cc.closeRequested()
            }
        }
    }

    component Mini: Rectangle {
        id: mini
        property string label: ""
        property string command: ""

        implicitWidth: Math.max(26, labelText.implicitWidth + 12)
        implicitHeight: 22
        radius: 6
        color: hover.hovered ? cc.cardHover : cc.card
        border.width: 1
        border.color: cc.border

        Text {
            id: labelText
            anchors.centerIn: parent
            text: mini.label
            color: cc.fg
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 9
        }

        HoverHandler { id: hover }

        MouseArea {
            anchors.fill: parent
            onClicked: {
                if (mini.command)
                    Quickshell.execDetached(["sh", "-c", mini.command])
            }
        }
    }

    component VolumeRow: Rectangle {
        id: volume
        readonly property var sink: Pipewire.defaultAudioSink

        implicitHeight: 40
        radius: 8
        color: cc.card
        border.width: 1
        border.color: cc.border

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 9
            anchors.rightMargin: 9
            spacing: 8

            Text {
                text: {
                    const s = volume.sink
                    if (!s || !s.audio)
                        return "󰕾"
                    return s.audio.muted || s.audio.volume < 0.01 ? "󰝟" : "󰕾"
                }
                color: cc.fg
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 13

                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -6
                    onClicked: Quickshell.execDetached(["pamixer", "-t"])
                }
            }

            Item {
                Layout.fillWidth: true
                implicitHeight: 14

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    height: 4
                    radius: 2
                    color: cc.cardHover
                }

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width * Math.max(0, Math.min(1,
                        volume.sink && volume.sink.audio ? volume.sink.audio.volume : 0))
                    height: 4
                    radius: 2
                    color: cc.accent
                }

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    x: parent.width * Math.max(0, Math.min(1,
                        volume.sink && volume.sink.audio ? volume.sink.audio.volume : 0)) - 5
                    width: 10
                    height: 10
                    radius: 5
                    color: cc.fg
                }

                MouseArea {
                    anchors.fill: parent
                    onPressed: (mouse) => apply(mouse.x)
                    onPositionChanged: (mouse) => {
                        if (pressed)
                            apply(mouse.x)
                    }
                    function apply(x) {
                        if (volume.sink && volume.sink.audio)
                            volume.sink.audio.volume = Math.max(0, Math.min(1, x / width))
                    }
                }
            }

            Text {
                width: 34
                horizontalAlignment: Text.AlignRight
                text: volume.sink && volume.sink.audio
                    ? Math.round(volume.sink.audio.volume * 100) + "%"
                    : "--"
                color: cc.dim
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 9
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: 11
        color: cc.bg
        border.width: 1
        border.color: cc.border

        ColumnLayout {
            id: content
            anchors.fill: parent
            anchors.margins: 14
            spacing: 9

            RowLayout {
                Layout.fillWidth: true

                Text {
                    text: cc.page === "quick" ? "Quick Menu" : "Control Center"
                    color: cc.fg
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 11
                    font.bold: true
                }

                Item { Layout.fillWidth: true }

                Text {
                    text: "✕"
                    color: cc.dim
                    font.pixelSize: 12

                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -8
                        onClicked: cc.closeRequested()
                    }
                }
            }

            GridLayout {
                visible: cc.page === "control"
                Layout.fillWidth: true
                columns: 2
                columnSpacing: 8
                rowSpacing: 8

                Tile {
                    glyph: "󰤢"
                    label: "Wi-Fi"
                    subCommand: "nmcli -t -f ACTIVE,SSID dev wifi 2>/dev/null | awk -F: '$1==\"yes\"{print $2; f=1} END{if(!f) print \"Off\"}'"
                    command: "nmcli radio wifi toggle"
                }
                Tile {
                    glyph: "󰂯"
                    label: "Bluetooth"
                    subCommand: "bluetoothctl show 2>/dev/null | awk '/Powered: yes/{print \"On\"; f=1} END{if(!f) print \"Off\"}'"
                    command: "bluetoothctl power toggle"
                }
            }

            VolumeRow { visible: cc.page === "control"; Layout.fillWidth: true }

            Rectangle {
                visible: cc.page === "control"
                Layout.fillWidth: true
                implicitHeight: 44
                radius: 8
                color: cc.card
                border.width: 1
                border.color: cc.border

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 9
                    anchors.rightMargin: 9
                    spacing: 6

                    Text {
                        text: "Kanata"
                        color: cc.fg
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 10
                        font.bold: true
                    }

                    ScriptLabel {
                        Layout.fillWidth: true
                        command: "hypr-kanata-status | jq -r '.text // \"absent\"'"
                        interval: 5
                        textColor: cc.dim
                    }

                    Mini { label: "HR"; command: "$HOME/.config/kanata/switch-kanata.sh homerow" }
                    Mini { label: "off"; command: "$HOME/.config/kanata/switch-kanata.sh disabled" }
                    Mini { label: "↻"; command: "$HOME/.config/kanata/reload-kanata.sh restart" }
                }
            }

            GridLayout {
                visible: cc.page === "control"
                Layout.fillWidth: true
                columns: 2
                columnSpacing: 8
                rowSpacing: 8

                Tile { glyph: "󰌾"; label: "Lock"; command: "hyprlock-session start" }
                Tile { glyph: "󰐥"; label: "Power"; command: "wlogout" }
            }

            GridLayout {
                visible: cc.page === "quick"
                Layout.fillWidth: true
                columns: 2
                columnSpacing: 8
                rowSpacing: 8

                Tile { glyph: "󰀻"; label: "Apps"; command: "nwg-drawer" }
                Tile { glyph: "󰒓"; label: "Profiles"; command: "hypr-profile" }
                Tile { glyph: "󰌌"; label: "Keyboard"; command: "hypr-toggle-kb" }
                Tile { glyph: "󰑓"; label: "Rotate"; command: "hypr-iio-toggle" }
            }

            Rectangle {
                visible: cc.page === "quick"
                Layout.fillWidth: true
                implicitHeight: 44
                radius: 8
                color: cc.card
                border.width: 1
                border.color: cc.border

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 9
                    anchors.rightMargin: 9
                    spacing: 8

                    Text {
                        Layout.fillWidth: true
                        text: "Brightness"
                        color: cc.fg
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 10
                    }
                    Mini { label: "−"; command: "brightness-ctl down 5" }
                    Mini { label: "+"; command: "brightness-ctl up 5" }
                }
            }

            Rectangle {
                visible: cc.page === "quick"
                Layout.fillWidth: true
                implicitHeight: 44
                radius: 8
                color: cc.card
                border.width: 1
                border.color: cc.border

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 9
                    anchors.rightMargin: 9
                    spacing: 8

                    Text {
                        Layout.fillWidth: true
                        text: "Volume"
                        color: cc.fg
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 10
                    }
                    Mini { label: "−"; command: "change-volume -5" }
                    Mini { label: "+"; command: "change-volume +5" }
                }
            }

            GridLayout {
                visible: cc.page === "quick"
                Layout.fillWidth: true
                columns: 2
                columnSpacing: 8
                rowSpacing: 8

                Tile { glyph: "󰌾"; label: "Lock"; command: "hyprlock-session start" }
                Tile { glyph: "󰐥"; label: "Power"; command: "wlogout" }
            }
        }
    }
}
