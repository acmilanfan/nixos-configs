import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

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
            onOpenKanata: {
                root.popoverScreen = modelData
                root.popover = "control"
                controlCenter.detail = "kanata"
            }
        }
    }

    IpcHandler {
        target: "shell"

        function control(): string {
            root.popoverScreen = Quickshell.screens[0]
            root.popover = "control"
            return "ok"
        }

        function quick(): string {
            root.popoverScreen = Quickshell.screens[0]
            root.popover = "quick"
            return "ok"
        }

        function close(): string {
            root.popover = ""
            return "ok"
        }

        function workspace(id: string): string {
            Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.focus({workspace = \u0027" + id + "\u0027})"])
            return "ok"
        }
    }

    ControlCenter {
        id: controlCenter
        page: root.popover
        targetScreen: root.popoverScreen
        onCloseRequested: root.popover = ""
    }
}
