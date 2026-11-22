import QtQuick
import Quickshell
import Quickshell.Io

ShellRoot {
    id: root

    property bool dual: true
    property string popover: ""
    property var popoverScreen: null

    FileView {
        path: Quickshell.env("XDG_RUNTIME_DIR") + "/yb-mode/mode"
        watchChanges: true
        onFileChanged: reload()
        onTextChanged: root.dual = text().trim() === "" || text().trim() === "dual"
    }

    function open(page, screen) {
        if (root.popover === page && root.popoverScreen === screen) {
            root.popover = ""
            return
        }
        root.popoverScreen = screen
        root.popover = page
    }

    Variants {
        model: Quickshell.screens

        Bar {
            required property var modelData
            screen: modelData
            dual: root.dual
            onOpenControlCenter: root.open("control", modelData)
            onOpenQuickMenu: root.open("quick", modelData)
        }
    }

    ControlCenter {
        page: root.popover
        targetScreen: root.popoverScreen
        onCloseRequested: root.popover = ""
    }
}
