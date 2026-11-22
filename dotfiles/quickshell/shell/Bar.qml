import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.UPower
import Quickshell.Services.Pipewire
import Quickshell.Services.SystemTray

PanelWindow {
    id: bar

    property bool dual: true

    readonly property string screenName: screen ? screen.name : ""
    readonly property bool bottom: screenName === "eDP-2"
    readonly property var bank: screenName === "eDP-1"
        ? [11, 12, 13, 14, 15, 16, 17, 18, 19, 20]
        : [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
    readonly property var monitor: Hyprland.monitorFor(screen)
    readonly property int activeWorkspaceId: monitor && monitor.activeWorkspace
        ? monitor.activeWorkspace.id : -1


    readonly property color background: "#101010"
    readonly property color foreground: "#c6d0f5"
    readonly property color muted: "#babbf1"
    readonly property color accent: "#7b5cff"

    visible: !bottom || dual
    anchors {
        top: true
        left: true
        right: true
    }
    margins {
        top: 4
        left: 4
        right: 4
    }
    implicitHeight: 26
    exclusiveZone: 30
    color: "transparent"
    WlrLayershell.namespace: "quickshell-shell"

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    PwObjectTracker {
        objects: Pipewire.defaultAudioSink ? [Pipewire.defaultAudioSink] : []
    }

    RowLayout {
        anchors.fill: parent
        spacing: 8

        Rectangle {
            Layout.fillHeight: true
            implicitHeight: 24
            implicitWidth: leftRow.implicitWidth + 16
            radius: 8
            color: bar.background

            RowLayout {
                id: leftRow
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                spacing: 10

                Row {
                    spacing: 3

                    Repeater {
                        model: bar.bank

                        delegate: Rectangle {
                            id: pill
                            required property int modelData

                            readonly property bool active: bar.activeWorkspaceId === modelData
                            readonly property var ws: {
                                const values = Hyprland.workspaces.values
                                for (let i = 0; i < values.length; i++)
                                    if (values[i].id === modelData)
                                        return values[i]
                                return null
                            }
                            readonly property bool occupied: ws !== null
                                && ws.toplevels.values.length > 0

                            width: 18
                            height: 18
                            radius: 5
                            color: active ? bar.accent : "transparent"
                            border.width: occupied && !active ? 1 : 0
                            border.color: bar.muted

                            Text {
                                anchors.centerIn: parent
                                text: pill.modelData
                                color: pill.active ? bar.background
                                    : (pill.occupied ? bar.foreground : bar.muted)
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 10
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: Hyprland.dispatch("workspace " + pill.modelData)
                            }
                        }
                    }
                }

                ScriptLabel {
                    visible: bar.monitor && bar.monitor.focused
                    command: "hyprctl -j activewindow | jq -r '(.title // \"\")[0:50]'"
                    interval: 2
                }

                ScriptLabel {
                    command: "hypr-idle-inhibit status >/dev/null 2>&1 && echo '󰅶' || echo '󰒲'"
                    interval: 2
                    leftCommand: "hypr-idle-inhibit toggle"
                }

                Item {
                    implicitWidth: touch.implicitWidth
                    implicitHeight: 18

                    Text {
                        id: touch
                        anchors.centerIn: parent
                        text: "󰀻"
                        color: bar.foreground
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 11
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: Quickshell.execDetached(["hypr-touch-menu"])
                    }
                }
            }
        }

        Item { Layout.fillWidth: true }

        Rectangle {
            Layout.fillHeight: true
            implicitHeight: 24
            implicitWidth: clockLabel.implicitWidth + 16
            radius: 8
            color: bar.background

            Text {
                id: clockLabel
                anchors.centerIn: parent
                text: Qt.formatDateTime(clock.date, "yyyy-MM-dd HH:mm")
                color: bar.foreground
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 11
            }
        }

        Item { Layout.fillWidth: true }

        Rectangle {
            Layout.fillHeight: true
            implicitHeight: 24
            implicitWidth: rightRow.implicitWidth + 16
            radius: 8
            color: bar.background

            RowLayout {
                id: rightRow
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                spacing: 9

                ScriptLabel {
                    command: "hypr-kanata-status | jq -r '.text // \"\"'"
                    interval: 5
                    leftCommand: "$HOME/.config/kanata/switch-kanata.sh homerow"
                    rightCommand: "$HOME/.config/kanata/switch-kanata.sh disabled"
                }

                ScriptLabel {
                    command: "hypr-layout-status | jq -r '.text // \"\"'"
                    interval: 2
                }

                ScriptLabel {
                    command: "hypr-power-watts | jq -r '.text // \"\"'"
                    interval: 30
                }

                ScriptLabel {
                    command: "hypr-timer output | jq -r '.text // \"\"'"
                    interval: 1
                    leftCommand: "hypr-timer stop"
                    rightCommand: "hypr-timer reset"
                    middleCommand: "hypr-timer start 25"
                }

                ScriptLabel {
                    command: "hypr-ai-agents | jq -r '.text // \"\"'"
                    interval: 10
                    leftCommand: "hypr-ai-agents --menu"
                }

                Text {
                    readonly property var sink: Pipewire.defaultAudioSink
                    text: !sink || !sink.audio ? "--"
                        : (sink.audio.muted ? "muted"
                            : Math.round(sink.audio.volume * 100) + "%")
                    color: bar.muted
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 11
                }

                Text {
                    text: UPower.displayDevice.ready
                        ? Math.round(UPower.displayDevice.percentage * 100) + "%"
                        : "--"
                    color: bar.muted
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 11
                }

                ScriptLabel {
                    command: "nmcli -t -f TYPE,STATE device 2>/dev/null | awk -F: '$2==\"connected\"{print ($1==\"wifi\"?\"󰤢\":\"󰈀\"); f=1; exit} END{if(!f) print \"󰤠\"}'"
                    interval: 5
                }

                ScriptLabel {
                    command: "top -bn1 | awk '/Cpu\\(s\\)/ {printf \"%d%%\", 100-$8}'"
                    interval: 2
                }

                ScriptLabel {
                    command: "free -m | awk '/Mem:/ {printf \"%d%%\", $3/$2*100}'"
                    interval: 30
                }

                Row {
                    spacing: 8

                    Repeater {
                        model: SystemTray.items

                        delegate: Image {
                            required property var modelData
                            source: modelData.icon
                            sourceSize.width: 16
                            sourceSize.height: 16
                            width: 16
                            height: 16

                            MouseArea {
                                anchors.fill: parent
                                onClicked: (mouse) => modelData.display(bar, mouse.x, mouse.y)
                            }
                        }
                    }
                }
            }
        }
    }
}
