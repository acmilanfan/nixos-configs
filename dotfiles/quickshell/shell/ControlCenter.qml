import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.UPower
import Quickshell.Services.Pipewire

PanelWindow {
    id: cc

    property string page: ""
    property var targetScreen: null
    signal closeRequested()

    readonly property color background: "#14141c"
    readonly property color border: "#252536"
    readonly property color foreground: "#c6d0f5"
    readonly property color muted: "#7f849c"

    visible: page !== ""
    screen: targetScreen
    anchors {
        top: true
        left: page === "quick"
        right: page === "control"
    }
    margins {
        top: 22
        left: 2
        right: 2
    }
    implicitWidth: 300
    implicitHeight: content.implicitHeight + 20
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
        property string command: ""

        Layout.fillWidth: true
        implicitHeight: 38
        radius: 7
        color: hover.hovered ? "#232334" : "#1b1b26"
        border.width: 1
        border.color: cc.border

        ColumnLayout {
            anchors.centerIn: parent
            spacing: 0

            Text {
                Layout.alignment: Qt.AlignHCenter
                text: tile.glyph
                color: cc.foreground
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 12
            }

            Text {
                Layout.alignment: Qt.AlignHCenter
                text: tile.label
                color: cc.muted
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 8
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

        implicitWidth: Math.max(24, labelText.implicitWidth + 10)
        implicitHeight: 20
        radius: 5
        color: hover.hovered ? "#232334" : "#1b1b26"
        border.width: 1
        border.color: cc.border

        Text {
            id: labelText
            anchors.centerIn: parent
            text: mini.label
            color: cc.foreground
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

    Rectangle {
        anchors.fill: parent
        radius: 10
        color: cc.background
        border.width: 1
        border.color: cc.border

        ColumnLayout {
            id: content
            anchors.fill: parent
            anchors.margins: 10
            spacing: 6

            RowLayout {
                Layout.fillWidth: true

                Text {
                    text: cc.page === "quick" ? "Quick Menu" : "Control Center"
                    color: cc.foreground
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 10
                    font.bold: true
                }

                Item { Layout.fillWidth: true }

                Text {
                    text: "✕"
                    color: cc.muted
                    font.pixelSize: 11

                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -6
                        onClicked: cc.closeRequested()
                    }
                }
            }

            // --- Control Center ---
            ColumnLayout {
                visible: cc.page === "control"
                Layout.fillWidth: true
                spacing: 5

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 5

                    ScriptLabel {
                        Layout.fillWidth: true
                        command: "nmcli -t -f ACTIVE,SSID dev wifi 2>/dev/null | awk -F: '$1==\"yes\"{print \"Wi-Fi: \" $2; f=1} END{if(!f) print \"Wi-Fi: off\"}'"
                        interval: 5
                    }
                    Mini { label: "toggle"; command: "nmcli radio wifi toggle" }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 5

                    ScriptLabel {
                        Layout.fillWidth: true
                        command: "bluetoothctl show 2>/dev/null | awk '/Powered: yes/{print \"Bluetooth: on\"; f=1} END{if(!f) print \"Bluetooth: off\"}'"
                        interval: 5
                    }
                    Mini { label: "toggle"; command: "bluetoothctl power toggle" }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 5

                    Text {
                        Layout.fillWidth: true
                        readonly property var sink: Pipewire.defaultAudioSink
                        text: !sink || !sink.audio ? "Audio: --"
                            : (sink.audio.muted ? "Audio: muted"
                                : "Audio: " + Math.round(sink.audio.volume * 100) + "%")
                        color: cc.foreground
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 9
                    }
                    Mini { label: "−"; command: "change-volume -5" }
                    Mini { label: "mute"; command: "pamixer -t" }
                    Mini { label: "+"; command: "change-volume +5" }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 5

                    Text {
                        Layout.fillWidth: true
                        text: "Kanata"
                        color: cc.foreground
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 9
                    }
                    Mini { label: "HR"; command: "$HOME/.config/kanata/switch-kanata.sh homerow" }
                    Mini { label: "off"; command: "$HOME/.config/kanata/switch-kanata.sh disabled" }
                    Mini { label: "reload"; command: "$HOME/.config/kanata/reload-kanata.sh restart" }
                }

                GridLayout {
                    Layout.fillWidth: true
                    columns: 2
                    columnSpacing: 5
                    rowSpacing: 5

                    Tile { glyph: "󰌾"; label: "Lock"; command: "hyprlock-session start" }
                    Tile { glyph: "󰐥"; label: "Power"; command: "wlogout" }
                }
            }

            // --- Quick Menu (touch) ---
            ColumnLayout {
                visible: cc.page === "quick"
                Layout.fillWidth: true
                spacing: 5

                GridLayout {
                    Layout.fillWidth: true
                    columns: 2
                    columnSpacing: 5
                    rowSpacing: 5

                    Tile { glyph: "󰀻"; label: "Apps"; command: "nwg-drawer" }
                    Tile { glyph: "󰒓"; label: "Profiles"; command: "hypr-profile" }
                    Tile { glyph: "󰌌"; label: "Keyboard"; command: "hypr-toggle-kb" }
                    Tile { glyph: "󰑓"; label: "Rotate"; command: "hypr-iio-toggle" }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 5

                    Text {
                        Layout.fillWidth: true
                        text: "Brightness"
                        color: cc.foreground
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 9
                    }
                    Mini { label: "−"; command: "brightness-ctl down 5" }
                    Mini { label: "+"; command: "brightness-ctl up 5" }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 5

                    Text {
                        Layout.fillWidth: true
                        text: "Volume"
                        color: cc.foreground
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 9
                    }
                    Mini { label: "−"; command: "change-volume -5" }
                    Mini { label: "+"; command: "change-volume +5" }
                }

                GridLayout {
                    Layout.fillWidth: true
                    columns: 2
                    columnSpacing: 5
                    rowSpacing: 5

                    Tile { glyph: "󰌾"; label: "Lock"; command: "hyprlock-session start" }
                    Tile { glyph: "󰐥"; label: "Power"; command: "wlogout" }
                }
            }
        }
    }
}
