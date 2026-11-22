import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Pipewire
import Quickshell.Services.SystemTray

PanelWindow {
    id: bar

    property bool dual: true
    signal openControlCenter()
    signal openQuickMenu()
    signal openKanata()

    readonly property string screenName: screen ? screen.name : ""
    readonly property bool bottom: screenName === "eDP-2"
    readonly property var bank: screenName === "eDP-1"
        ? [11, 12, 13, 14, 15, 16, 17, 18, 19, 20]
        : [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
    readonly property var monitor: Hyprland.monitorFor(screen)
    readonly property int activeWorkspaceId: monitor && monitor.activeWorkspace
        ? monitor.activeWorkspace.id : -1

    readonly property color background: "#14141c"
    readonly property color border: "#252536"
    readonly property color foreground: "#c6d0f5"
    readonly property color muted: "#7f849c"
    readonly property color accent: "#7b5cff"

    visible: !bottom || dual
    anchors {
        top: true
        left: true
        right: true
    }
    margins {
        top: 3
        left: 3
        right: 3
    }
    implicitHeight: 28
    exclusiveZone: 31
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
        spacing: 4

        Item {
            Layout.fillWidth: true
            Layout.preferredWidth: 0
            implicitHeight: 28

            Rectangle {
                width: leftRow.implicitWidth + 10
                height: parent.height
                radius: 6
                color: bar.background
                border.width: 1
                border.color: bar.border

                RowLayout {
                    id: leftRow
                    anchors.fill: parent
                    anchors.leftMargin: 5
                    anchors.rightMargin: 5
                    spacing: 6

                    Row {
                        spacing: 2

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

                                visible: active || occupied
                                width: 19
                                height: 19
                                radius: 4
                                color: active ? bar.accent
                                    : (hover.hovered ? "#242436" : "transparent")

                                Text {
                                    anchors.centerIn: parent
                                    text: pill.modelData
                                    color: pill.active ? bar.background : bar.foreground
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 13
                                }

                                HoverHandler { id: hover }

                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: Hyprland.dispatch("workspace " + pill.modelData)
                                }
                            }
                        }
                    }

                    ScriptLabel {
                        visible: bar.monitor && bar.monitor.focused
                        command: "hyprctl -j activewindow | jq -r '(.title // \"\")[0:38]'"
                        interval: 2
                    }

                    ScriptLabel {
                        command: "hypr-idle-inhibit status >/dev/null 2>&1 && echo '󰅶' || echo '󰒲'"
                        interval: 2
                        leftCommand: "hypr-idle-inhibit toggle"
                    }

                    Item {
                        implicitWidth: touch.implicitWidth
                        implicitHeight: 14

                        Text {
                            id: touch
                            anchors.centerIn: parent
                            text: "󰀻"
                            color: bar.foreground
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 15
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: bar.openQuickMenu()
                        }
                    }
                }
            }
        }

        Rectangle {
            width: clockLabel.implicitWidth + 12
            height: 24
            radius: 6
            color: bar.background
            border.width: 1
            border.color: bar.border

            Text {
                id: clockLabel
                anchors.centerIn: parent
                text: Qt.formatDateTime(clock.date, "HH:mm")
                color: bar.foreground
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 16
            }

            MouseArea {
                anchors.fill: parent
                onClicked: bar.openControlCenter()
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.preferredWidth: 0
            implicitHeight: 28

            Rectangle {
                anchors.right: parent.right
                width: rightRow.implicitWidth + 10
                height: parent.height
                radius: 6
                color: bar.background
                border.width: 1
                border.color: bar.border

                RowLayout {
                    id: rightRow
                    anchors.fill: parent
                    anchors.leftMargin: 5
                    anchors.rightMargin: 5
                    spacing: 6

                    ScriptLabel {
                        visible: text !== ""
                        command: "hypr-kanata-status | jq -r '.text // \"\"'"
                        interval: 5
                        onClicked: bar.openKanata()
                    }

                    ScriptLabel {
                        command: "hypr-layout-icon"
                        interval: 2
                        leftCommand: "hypr-cycle-layout"
                    }

                    ScriptLabel {
                        command: "hypr-power-watts | jq -r '.text // \"\"'"
                        interval: 30
                        onClicked: bar.openControlCenter()
                    }

                    ScriptLabel {
                        visible: text !== ""
                        command: "hypr-timer output | jq -r 'if .class == \"finished\" then \"\" else (.text // \"\") end'"
                        interval: 1
                        leftCommand: "hypr-timer stop"
                        rightCommand: "hypr-timer reset"
                        middleCommand: "hypr-timer start 25"
                    }

                    ScriptLabel {
                        visible: text !== ""
                        command: "hypr-ai-agents | jq -r '.text // \"\"'"
                        interval: 10
                        leftCommand: "hypr-ai-agents --menu"
                    }

                    Text {
                        readonly property var sink: Pipewire.defaultAudioSink
                        text: !sink || !sink.audio ? "󰕾 --"
                            : (sink.audio.muted ? "󰝟 muted"
                                : "󰕾 " + Math.round(sink.audio.volume * 100) + "%")
                        color: bar.muted
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 15

                        MouseArea {
                            anchors.fill: parent
                            onClicked: bar.openControlCenter()
                        }
                    }

                    ScriptLabel {
                        visible: text !== ""
                        command: "upower -i /org/freedesktop/UPower/devices/DisplayDevice 2>/dev/null | awk '/state:/{s=$2} /percentage:/{p=$2} END{if (s==\"charging\"||s==\"discharging\") printf \"󰁹 %s\", p}'"
                        interval: 30
                        onClicked: bar.openControlCenter()
                    }

                    ScriptLabel {
                        command: "nmcli -t -f TYPE,STATE device 2>/dev/null | awk -F: '$2==\"connected\"{print ($1==\"wifi\"?\"󰤢\":\"󰈀\"); f=1; exit} END{if(!f) print \"󰤠\"}'"
                        interval: 5
                        onClicked: bar.openControlCenter()
                    }

                    ScriptLabel {
                        command: "top -bn1 | awk '/Cpu\\(s\\)/ {printf \"󰻠 %d%%\", 100-$8}'"
                        interval: 2
                        onClicked: bar.openControlCenter()
                    }

                    ScriptLabel {
                        command: "free -m | awk '/Mem:/ {printf \"󰍛 %d%%\", $3/$2*100}'"
                        interval: 30
                        onClicked: bar.openControlCenter()
                    }

                    Row {
                        spacing: 5

                        Repeater {
                            model: SystemTray.items

                            delegate: Image {
                                required property var modelData
                                source: modelData.icon
                                sourceSize.width: 12
                                sourceSize.height: 12
                                width: 12
                                height: 12

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
}
