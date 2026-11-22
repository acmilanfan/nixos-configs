import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.UPower
import Quickshell.Services.Pipewire

// Pilot bar for eDP-2 only. Start/stop through hypr-quickshell-pilot.
ShellRoot {
    id: root

    readonly property color background: "#101010"
    readonly property color foreground: "#c6d0f5"
    readonly property color accent: "#7b5cff"
    readonly property color dim: "#babbf1"

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    PwObjectTracker {
        objects: Pipewire.defaultAudioSink ? [Pipewire.defaultAudioSink] : []
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: bar
            required property var modelData
            screen: modelData
            visible: modelData.name === "eDP-2"

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
            implicitHeight: 28
            exclusiveZone: 32
            color: "transparent"
            WlrLayershell.namespace: "quickshell-pilot"

            readonly property var monitor: Hyprland.monitorFor(screen)
            readonly property int activeWorkspaceId: monitor && monitor.activeWorkspace
                ? monitor.activeWorkspace.id
                : -1

            Rectangle {
                anchors.fill: parent
                radius: 8
                color: root.background

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 14

                    Row {
                        spacing: 4

                        Repeater {
                            model: 10

                            delegate: Rectangle {
                                id: pill
                                required property int index

                                readonly property int wsId: index + 1
                                readonly property var ws: {
                                    const values = Hyprland.workspaces.values
                                    for (let i = 0; i < values.length; i++)
                                        if (values[i].id === wsId)
                                            return values[i]
                                    return null
                                }
                                readonly property bool active: bar.activeWorkspaceId === wsId
                                readonly property bool occupied: ws !== null
                                    && ws.toplevels.values.length > 0

                                width: Math.max(18, label.implicitWidth + 10)
                                height: 18
                                radius: 5
                                color: active ? root.accent : "transparent"
                                border.width: occupied && !active ? 1 : 0
                                border.color: root.dim

                                Text {
                                    id: label
                                    anchors.centerIn: parent
                                    text: pill.wsId
                                    color: pill.active ? root.background
                                        : (pill.occupied ? root.foreground : root.dim)
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 11
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: Hyprland.dispatch("workspace " + pill.wsId)
                                }
                            }
                        }
                    }

                    Item { Layout.fillWidth: true }

                    Text {
                        text: Qt.formatDateTime(clock.date, "HH:mm")
                        color: root.foreground
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 12
                    }

                    Item { Layout.fillWidth: true }

                    Text {
                        text: UPower.displayDevice.ready
                            ? Math.round(UPower.displayDevice.percentage) + "%"
                            : "--"
                        color: root.dim
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 12
                    }

                    Text {
                        readonly property var sink: Pipewire.defaultAudioSink
                        text: !sink || !sink.audio
                            ? "--"
                            : (sink.audio.muted
                                ? "muted"
                                : Math.round(sink.audio.volume * 100) + "%")
                        color: root.dim
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 12
                    }
                }
            }
        }
    }
}
