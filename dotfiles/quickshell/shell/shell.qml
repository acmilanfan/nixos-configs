import QtQuick
import Quickshell
import Quickshell.Io

ShellRoot {
    id: root

    // The bottom panel is only meaningful in dual-screen mode. Unknown output
    // (yb-mode absent) counts as dual so non-Yoga hosts are unaffected.
    property bool dual: true

    Process {
        id: mode
        command: ["sh", "-c", "yb-mode status 2>/dev/null | sed -n 's/.*mode=\\([^ ]*\\).*/\\1/p'"]
        stdout: StdioCollector {
            onStreamFinished: root.dual = this.text.trim() === "" || this.text.trim() === "dual"
        }
    }

    Timer {
        interval: 2000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: mode.running = true
    }

    Variants {
        model: Quickshell.screens

        Bar {
            required property var modelData
            screen: modelData
            dual: root.dual
        }
    }
}
