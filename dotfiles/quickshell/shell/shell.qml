import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

ShellRoot {
    id: root

    property bool dual: true
    property bool showTop: true
    property bool showBottom: true
    property bool showExternal: true
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
            enabled: modelData.name === "eDP-1" ? root.showTop
                : modelData.name === "eDP-2" ? root.showBottom
                : root.showExternal
            onOpenControlCenter: root.open("control", modelData)
            onOpenQuickMenu: root.open("quick", modelData)
            onOpenKanata: {
                if (root.popover === "control" && controlCenter.detail === "kanata") {
                    root.popover = ""
                    return
                }
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

        function bars(mode: string): string {
            if (mode === "all-on") {
                root.showTop = true
                root.showBottom = true
                root.showExternal = true
            } else if (mode === "all-off") {
                root.showTop = false
                root.showBottom = false
                root.showExternal = false
            } else if (mode === "top") {
                root.showTop = !root.showTop
            } else if (mode === "bottom") {
                root.showBottom = !root.showBottom
            } else if (mode === "external") {
                root.showExternal = !root.showExternal
            } else if (mode === "all") {
                const show = !(root.showTop || root.showBottom || root.showExternal)
                root.showTop = show
                root.showBottom = show
                root.showExternal = show
            } else if (mode === "both") {
                const show = !(root.showTop && root.showBottom)
                root.showTop = show
                root.showBottom = show
            }
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
