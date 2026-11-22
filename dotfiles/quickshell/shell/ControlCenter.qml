import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.UPower
import Quickshell.Services.Pipewire

PanelWindow {
    id: cc

    property bool open: false
    signal closeRequested()

    readonly property color background: "#14141c"
    readonly property color border: "#252536"
    readonly property color foreground: "#c6d0f5"
    readonly property color muted: "#7f849c"

    visible: open
    anchors {
        top: true
        right: true
    }
    margins {
        top: 28
        right: 8
    }
    implicitWidth: 318
    implicitHeight: content.implicitHeight + 24
    exclusiveZone: 0
    color: "transparent"
    WlrLayershell.namespace: "quickshell-control-center"

    PwObjectTracker {
        objects: Pipewire.defaultAudioSink ? [Pipewire.defaultAudioSink] : []
    }

    component CcButton: Rectangle {
        id: button
        property string glyph: ""
        property string label: ""
        property string command: ""

        Layout.fillWidth: true
        implicitHeight: 42
        radius: 8
        color: hover.hovered ? "#232334" : "#1b1b26"
        border.width: 1
        border.color: cc.border

        ColumnLayout {
            anchors.centerIn: parent
            spacing: 1

            Text {
                Layout.alignment: Qt.AlignHCenter
                text: button.glyph
                color: cc.foreground
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 13
            }

            Text {
                Layout.alignment: Qt.AlignHCenter
                text: button.label
                color: cc.muted
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 9
            }
        }

        HoverHandler { id: hover }

        MouseArea {
            anchors.fill: parent
            onClicked: {
                if (button.command)
                    Quickshell.execDetached(["sh", "-c", button.command])
                cc.closeRequested()
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: 12
        color: cc.background
        border.width: 1
        border.color: cc.border

        ColumnLayout {
            id: content
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            RowLayout {
                Layout.fillWidth: true

                Text {
                    text: "Control Center"
                    color: cc.foreground
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 11
                    font.bold: true
                }

                Item { Layout.fillWidth: true }

                Text {
                    text: "✕"
                    color: cc.muted
                    font.pixelSize: 12

                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -6
                        onClicked: cc.closeRequested()
                    }
                }
            }

            GridLayout {
                Layout.fillWidth: true
                columns: 2
                columnSpacing: 6
                rowSpacing: 6

                CcButton {
                    glyph: "󰤢"
                    label: "Wi-Fi"
                    command: "iwmenu -l custom --launcher-command 'vicinae dmenu -p \"{hint}\"'"
                }
                CcButton {
                    glyph: "󰂯"
                    label: "Bluetooth"
                    command: "bzmenu -l custom --launcher-command 'vicinae dmenu -p \"{hint}\"'"
                }
                CcButton {
                    glyph: "󰕾"
                    label: "Audio"
                    command: "pwmenu -l custom --launcher-command 'vicinae dmenu -p \"{hint}\"'"
                }
                CcButton {
                    glyph: "󰌌"
                    label: "Kanata"
                    command: "hypr-kanata-menu"
                }
                CcButton {
                    glyph: "󰌾"
                    label: "Lock"
                    command: "hyprlock-session start"
                }
                CcButton {
                    glyph: "󰐥"
                    label: "Power"
                    command: "wlogout"
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 1
                color: cc.border
            }

            RowLayout {
                Layout.fillWidth: true

                Text {
                    readonly property var sink: Pipewire.defaultAudioSink
                    text: !sink || !sink.audio ? "audio --"
                        : (sink.audio.muted ? "audio muted"
                            : "audio " + Math.round(sink.audio.volume * 100) + "%")
                    color: cc.muted
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 10
                }

                Item { Layout.fillWidth: true }

                Text {
                    readonly property var device: UPower.displayDevice
                    text: device && device.ready
                        ? Math.round(device.percentage * 100) + "%"
                        : "--"
                    color: cc.muted
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 10
                }
            }
        }
    }
}
