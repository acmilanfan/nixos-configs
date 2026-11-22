import QtQuick
import Quickshell
import Quickshell.Io

// Polls a shell command and shows its output. Optional click commands run the
// same way Waybar's custom modules did.
Item {
    id: root

    property string command: ""
    property int interval: 5
    property string text: ""
    property string leftCommand: ""
    property string rightCommand: ""
    property string middleCommand: ""
    property color textColor: "#c6d0f5"
    signal clicked()

    implicitWidth: label.implicitWidth
    implicitHeight: 18

    Text {
        id: label
        anchors.centerIn: parent
        text: root.text
        color: root.textColor
        font.family: "JetBrainsMono Nerd Font"
        font.pixelSize: 16
    }

    Process {
        id: proc
        command: ["sh", "-c", root.command]
        stdout: StdioCollector {
            onStreamFinished: root.text = this.text.trim()
        }
    }

    Timer {
        interval: Math.max(1, root.interval) * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: proc.running = true
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onClicked: (mouse) => {
            const cmd = mouse.button === Qt.LeftButton ? root.leftCommand
                : mouse.button === Qt.RightButton ? root.rightCommand
                : root.middleCommand
            if (cmd)
                Quickshell.execDetached(["sh", "-c", cmd])
            else
                root.clicked()
        }
    }
}
