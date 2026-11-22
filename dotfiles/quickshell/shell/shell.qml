import QtQuick
import Quickshell
import Quickshell.Io

ShellRoot {
    id: root

    // The bottom panel is only meaningful in dual-screen mode. Unknown or
    // missing state (yb-mode absent) counts as dual so other hosts are fine.
    property bool dual: true

    FileView {
        path: Quickshell.env("XDG_RUNTIME_DIR") + "/yb-mode/mode"
        watchChanges: true
        onFileChanged: reload()
        onTextChanged: root.dual = text.trim() === "" || text.trim() === "dual"
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
